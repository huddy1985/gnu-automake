#! /bin/sh
# Copyright (C) 1996-2012 Free Software Foundation, Inc.
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

# Test to make sure name canonicalization happens for libtool libraries.
# Keep this in sync with sister test 'canon4.test'.

required='libtoolize'
. ./defs || exit 1

cat >> configure.ac << 'END'
AC_PROG_CC
AM_PROG_AR
AC_PROG_LIBTOOL
END

cat > Makefile.am << 'END'
noinst_LTLIBRARIES = libx-y.la
libx_y_la_SOURCES = xy.c
END

: > ltmain.sh
: > ar-lib

$ACLOCAL
$AUTOMAKE -a

grep '^ *libx-y.*=' Makefile.in && exit 1

: