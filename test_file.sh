#!/bin/bash
# @file libexample
# @brief A library that solves some common problems.
# @description
#     The project solves lots of problems:
#      * a
#      * b
#      * c
#      * etc

# SPDX-FileCopyrightText: (c) 2016 ale5000
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileType: SOURCE

# shellcheck disable=SC3043
# SC3043: In POSIX sh, local is undefined


# @section Example functions

# @description My super function.
# Not thread-safe.
#
# @example
#    echo "test: $(say-hello World)"
#
# @arg $1 string A value to print
#
# @exitcode 0 If successful.
# @exitcode 1 If an empty string passed.
#
# @see validate()
say-hello() {
    if [[ ! "$1" ]]; then
        return 1;
    fi

    echo "Hello $1"
}
