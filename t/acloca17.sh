#! /bin/sh
# Copyright (C) 2004-2012 Free Software Foundation, Inc.
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

# Make sure aclocal report unused required macros.

am_create_testdir=empty
. ./defs || exit 1

cat > configure.ac << 'END'
AC_INIT
SOME_DEFS
END

mkdir m4
cat >m4/somedefs.m4 <<EOF
AC_DEFUN([SOME_DEFS], [
  AC_REQUIRE([UNDEFINED_MACRO])
])
EOF

# FIXME: We want autom4te's 'undefined required macro' warning to be fatal,
# but have no means to say so to aclocal.  We use WARNINGS=error instead.

WARNINGS=error $ACLOCAL -I m4 2>stderr && { cat stderr >&2; exit 1; }
cat stderr >&2
grep '^configure\.ac:2:.*UNDEFINED_MACRO' stderr

:
