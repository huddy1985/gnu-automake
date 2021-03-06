#! /bin/sh
# Copyright (C) 1999-2012 Free Software Foundation, Inc.
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

# Test of flags specific to executable.

. ./defs || exit 1

cat >> configure.ac << 'END'
AC_PROG_CC
AM_PROG_CC_C_O
END

cat > Makefile.am << 'END'
AUTOMAKE_OPTIONS = no-dependencies
bin_PROGRAMS = foo
foo_SOURCES = foo.c
foo_CFLAGS = -DBAR
END

# Make sure 'compile' is required.
$ACLOCAL
AUTOMAKE_fails
grep 'required.*compile' stderr

: > compile

$AUTOMAKE

# Look for $(COMPILE) -c in .c.o rule.
grep 'COMPILE. [^-]' Makefile.in && exit 1

# Look for foo-foo.o.
grep '[^-]foo\.o' Makefile.in && exit 1

# Regression test for missing space.
$FGREP ')-c' Makefile.in && exit 1

exit 0
