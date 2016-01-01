"""Python implementation of the multi-tau correlation with partial data"""
# ######################################################################
# Copyright (c) 2014, Brookhaven Science Associates, Brookhaven        #
# National Laboratory. All rights reserved.                            #
#                                                                      #
# Redistribution and use in source and binary forms, with or without   #
# modification, are permitted provided that the following conditions   #
# are met:                                                             #
#                                                                      #
# * Redistributions of source code must retain the above copyright     #
#   notice, this list of conditions and the following disclaimer.      #
#                                                                      #
# * Redistributions in binary form must reproduce the above copyright  #
#   notice this list of conditions and the following disclaimer in     #
#   the documentation and/or other materials provided with the         #
#   distribution.                                                      #
#                                                                      #
# * Neither the name of the Brookhaven Science Associates, Brookhaven  #
#   National Laboratory nor the names of its contributors may be used  #
#   to endorse or promote products derived from this software without  #
#   specific prior written permission.                                 #
#                                                                      #
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS  #
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT    #
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS    #
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE       #
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,           #
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES   #
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR   #
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)   #
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,  #
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OTHERWISE) ARISING   #
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE   #
# POSSIBILITY OF SUCH DAMAGE.                                          #
########################################################################
from __future__ import absolute_import, division, print_function

from skxray.core.utils import multi_tau_lags
from skxray.core.roi import extract_label_indices
from skxray.core.correlation.cyprocess import cyprocess
from collections import namedtuple
import numpy as np
cimport numpy as np

results = namedtuple(
    'correlation_results',
    ['g2', 'lag_steps', 'internal_state']
)

cdef class InternalState:
    cdef np.ndarray buf
    cdef np.ndarray G
    cdef np.ndarray past_intensity
    cdef np.ndarray future_intensity
    cdef np.ndarray img_per_level
    cdef np.ndarray label_mask
    cdef np.ndarray track_level
    cdef np.ndarray cur
    cdef np.ndarray pixel_list
    cdef np.int_t processed
    cdef np.ndarray g2

    def __cinit__(self, np.int_t num_levels, np.int_t num_bufs,
                  np.ndarray[np.int_t, ndim=2] labels,
                  np.ndarray[np.int_t, ndim=1] label_mask,
                  np.ndarray[np.int_t, ndim=1] pixel_list,
                  np.int_t num_rois):
        self.pixel_list = pixel_list
        self.label_mask = label_mask
        # G holds the un normalized auto- correlation result. We
        # accumulate computations into G as the algorithm proceeds.
        self.G = np.zeros(((num_levels + 1) * num_bufs / 2, num_rois),
                            dtype=np.float64)
        self.g2 = np.zeros_like(self.G)
        # matrix for normalizing G into g2
        self.past_intensity = np.zeros_like(self.G)
        # matrix for normalizing G into g2
        self.future_intensity = np.zeros_like(self.G)
        # Ring buffer, a buffer with periodic boundary conditions.
        # Images must be keep for up to maximum delay in buf.
        self.buf = np.zeros((num_levels, num_bufs, len(self.pixel_list)),
                             dtype=np.float64)
        # to track how many images processed in each level
        self.img_per_level = np.zeros(num_levels, dtype=np.int64)
        # to track which levels have already been processed
        self.track_level = np.zeros(num_levels, dtype=bool)
        # to increment buffer
        self.cur = np.ones(num_levels, dtype=np.int64)
        # whether or not to process higher levels in multi-tau
        self.processed = 0


def lazy_multi_tau(np.ndarray[np.float_t, ndim=2] image,
                   long num_levels, long num_bufs,
                   np.ndarray[np.int_t, ndim=2] labels,
                   _state=None):
    """Generator implementation of 1-time multi-tau correlation

    Parameters
    ----------
    num_levels : int
        how many generations of downsampling to perform, i.e., the depth of
        the binomial tree of averaged frames
    num_bufs : int, must be even
        maximum lag step to compute in each generation of downsampling
    labels : array
        Labeled array of the same shape as the image stack.
        Each ROI is represented by sequential integers starting at one.  For
        example, if you have four ROIs, they must be labeled 1, 2, 3,
        4. Background is labeled as 0
    labels : array
        Labeled array of the same shape as the image stack.
        Each ROI is represented by sequential integers starting at one.  For
        example, if you have four ROIs, they must be labeled 1, 2, 3,
        4. Background is labeled as 0
    images : iterable of 2D arrays
    _state : namedtuple, optional
        _state is a bucket for all of the internal state of the generator.
        It is part of the `results` object that is yielded from this
        generator

    Yields
    ------
    state : namedtuple
        A 'results' object that contains:
        - the normalized correlation, `g2`
        - the times at which the correlation was computed, `lag_steps`
        - and all of the internal state, `final_state`, which is a
          `correlation_state` namedtuple

    Notes
    -----

    The normalized intensity-intensity time-autocorrelation function
    is defined as

    :math ::
        g_2(q, t') = \frac{<I(q, t)I(q, t + t')> }{<I(q, t)>^2}

    ; t' > 0

    Here, I(q, t) refers to the scattering strength at the momentum
    transfer vector q in reciprocal space at time t, and the brackets
    <...> refer to averages over time t. The quantity t' denotes the
    delay time

    This implementation is based on published work. [1]_

    References
    ----------

    .. [1] D. Lumma, L. B. Lurio, S. G. J. Mochrie and M. Sutton,
        "Area detector based photon correlation in the regime of
        short data batches: Data reduction for dynamic x-ray
        scattering," Rev. Sci. Instrum., vol 70, p 3274-3289, 2000.
    """
    if num_bufs % 2 != 0:
        raise ValueError("There must be an even number of `num_bufs`. You "
                         "provided %s" % num_bufs)
    if _state is None:
        label_mask, pixel_list = extract_label_indices(labels)
        # map the indices onto a sequential list of integers starting at 1
        label_mapping = {label: n for n, label in enumerate(
                np.unique(label_mask))}
        # remap the label mask to go from 0 -> max(_labels)
        for label, n in label_mapping.items():
            label_mask[label_mask == label] = n
        _state = InternalState(num_levels, num_bufs, labels, label_mask,
                               pixel_list, len(label_mapping))
    # create a shorthand reference to the results and state named tuple
    cdef InternalState s = _state
    # stash the number of pixels in the mask
    cdef np.ndarray num_pixels = np.bincount(s.label_mask)
    # Convert from num_levels, num_bufs to lag frames.
    cdef np.int_t tot_channels
    cdef np.int_t g_max
    cdef np.ndarray g2
    cdef np.ndarray lag_steps

    tot_channels, lag_steps = multi_tau_lags(num_levels, num_bufs)

    # iterate over the images to compute multi-tau correlation
    # Compute the correlations for all higher levels.
    cdef np.int_t level = 0

    # increment buffer
    s.cur[0] = (1 + s.cur[0]) % num_bufs

    # Put the ROI pixels into the ring buffer.
    s.buf[0, s.cur[0] - 1] = np.ravel(image)[s.pixel_list]
    buf_no = s.cur[0] - 1
    # Compute the correlations between the first level
    # (undownsampled) frames. This modifies G,
    # past_intensity, future_intensity,
    # and img_per_level in place!
    cyprocess(s.buf, s.G, s.past_intensity, s.future_intensity,
              s.label_mask, num_bufs, num_pixels, s.img_per_level,
              level, buf_no)

    # check whether the number of levels is one, otherwise
    # continue processing the next level
    cdef int processing = num_levels > 1

    level = 1
    while processing:
        if not s.track_level[level]:
            s.track_level[level] = True
            processing = False
        else:
            prev = (1 + (s.cur[level - 1] - 2) % num_bufs)
            s.cur[level] = (
                1 + s.cur[level] % num_bufs)

            # TODO clean this up. it is hard to understand
            s.buf[level, s.cur[level] - 1] = ((
                    s.buf[level - 1, prev - 1] +
                    s.buf[level - 1, s.cur[level - 1] - 1]
                ) / 2
            )

            # make the track_level zero once that level is processed
            s.track_level[level] = False

            # call processing_func for each multi-tau level greater
            # than one. This is modifying things in place. See comment
            # on previous call above.
            buf_no = s.cur[level] - 1
            cyprocess(s.buf, s.G, s.past_intensity,
                      s.future_intensity, s.label_mask, num_bufs,
                      num_pixels, s.img_per_level, level, buf_no)
            level += 1

            # Checking whether there is next level for processing
            processing = level < num_levels

    # If any past intensities are zero, then g2 cannot be normalized at
    # those levels. This if/else code block is basically preventing
    # divide-by-zero errors.
    if len(np.where(s.past_intensity == 0)[0]) != 0:
        g_max = np.where(s.past_intensity == 0)[0][0]
    else:
        g_max = s.past_intensity.shape[0]

    # Normalize g2 by the product of past_intensity and future_intensity
    s.g2 = (s.G[:g_max] /
            (s.past_intensity[:g_max] *
             s.future_intensity[:g_max]))

    s.processed += 1
    return results(s.g2, lag_steps[:g_max], s)
