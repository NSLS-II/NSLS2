'''
Copyright (c) 2014, Brookhaven National Laboratory
All rights reserved.

# @author: Li Li (lili@bnl.gov)
# created on 08/19/2014

Original code:
@author: Mirna Lerotic, 2nd Look Consulting
         http://www.2ndlookconsulting.com/
Copyright (c) 2013, Stefan Vogt, Argonne National Laboratory
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the Brookhaven National Laboratory nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
'''


from __future__ import (absolute_import, division)
import six

from numpy.testing import assert_array_equal

from nsls2.fitting.base.element import Element


def test_element_data():
    """
    smoke test of all elements
    """

    data1 = []
    data2 = []

    name_list = []
    for i in range(100):
        e = Element(i+1, 10.0)
        data1.append(e.cs['Ka1'])
        name_list.append(e.name)

    for item in name_list:
        e = Element(item, 10.0)
        data2.append(e.cs['Ka1'])

    assert_array_equal(data1, data2)

    return