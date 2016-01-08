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
import logging

import numpy as np
from numpy.testing import assert_array_almost_equal

import skbeam.core.utils as utils
from skbeam.core.correlation import (multi_tau_auto_corr,
                                     auto_corr_scat_factor,
                                     lazy_multi_tau)

logger = logging.getLogger(__name__)


def setup():
    global num_levels, num_bufs, xdim, ydim, stack_size, img_stack, rois
    num_levels = 6
    num_bufs = 4  # must be even
    xdim = 256
    ydim = 512
    stack_size = 100
    img_stack = np.random.randint(1, 3, (stack_size, xdim, ydim))
    rois = np.zeros_like(img_stack[0])
    # make sure that the ROIs can be any integers greater than 1. They do not
    # have to start at 1 and be continuous
    rois[0:xdim//10, 0:ydim//10] = 5
    rois[xdim//10:xdim//5, ydim//10:ydim//5] = 3


def test_lazy_vs_original():
    setup()
    # run the correlation on the full stack
    full_gen = lazy_multi_tau(
        img_stack, num_levels, num_bufs, rois)
    for gen_result in full_gen:
        pass

    g2, lag_steps = multi_tau_auto_corr(num_levels, num_bufs, rois, img_stack)

    assert np.all(g2 == gen_result.g2)
    assert np.all(lag_steps == gen_result.lag_steps)


def test_lazy_multi_tau():
    setup()
    # run the correlation on the full stack
    full_gen = lazy_multi_tau(
        img_stack, num_levels, num_bufs, rois)
    for full_result in full_gen:
        pass

    # make sure we have essentially zero correlation in the images,
    # since they are random integers
    assert np.average(full_result.g2-1) < 0.01

    # run the correlation on the first half
    gen_first_half = lazy_multi_tau(
        img_stack[:stack_size//2], num_levels, num_bufs, rois)
    for first_half_result in gen_first_half:
        pass
    # run the correlation on the second half by passing in the state from the
    # first half
    gen_second_half = lazy_multi_tau(
        img_stack[stack_size//2:], num_levels, num_bufs, rois,
        internal_state=first_half_result.internal_state
    )

    for second_half_result in gen_second_half:
        pass

    assert np.all(full_result.g2 == second_half_result.g2)


def test_auto_corr_scat_factor():
    num_levels, num_bufs = 3, 4
    tot_channels, lags = utils.multi_tau_lags(num_levels, num_bufs)
    beta = 0.5
    relaxation_rate = 10.0
    baseline = 1.0

    g2 = auto_corr_scat_factor(lags, beta, relaxation_rate, baseline)

    assert_array_almost_equal(g2, np.array([1.5, 1.0, 1.0, 1.0, 1.0,
                                            1.0, 1.0, 1.0]), decimal=8)


if __name__ == '__main__':
    import nose

    nose.runmodule(argv=['-s', '--with-doctest'], exit=False)