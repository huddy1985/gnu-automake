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

# Make sure C++ files are rewritten to ".o" and not just "o".
. ./defs || exit 1

cat >> configure.ac << 'END'
AC_PROG_CXX
END

cat > Makefile.am << 'END'
sbin_PROGRAMS = anonymous
anonymous_SOURCES = doe.C
END

: > doe.C

$ACLOCAL
$AUTOMAKE

$FGREP 'doe.$(OBJEXT)' Makefile.in
