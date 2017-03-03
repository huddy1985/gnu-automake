#! /bin/sh
# Copyright (C) 2001-2012 Free Software Foundation, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Test to make sure that noinst_* and check_* are not installed.
# From Pavel Roskin.

. ./defs || exit 1

cat > Makefile.am << 'END'
noinst_SCRIPTS = foo.sh
noinst_DATA = foo.xpm
noinst_LIBRARIES = libfoo.a
noinst_PROGRAMS = foo
noinst_HEADERS = foo.h
check_SCRIPTS = bar.sh
check_DATA = bar.xpm
check_LIBRARIES = libbar.a
check_PROGRAMS = bar
check_HEADERS = bar.h
END

cat >> configure.ac << 'END'
AC_PROG_CC
AM_PROG_AR
AC_PROG_RANLIB
END

: > ar-lib

$ACLOCAL
$AUTOMAKE

grep 'noinstdir' Makefile.in && exit 1
grep 'checkdir' Makefile.in && exit 1

:
