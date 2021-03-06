#! /bin/sh
# Copyright (C) 1998-2012 Free Software Foundation, Inc.
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

# Test to make sure that texinfo.tex is not required by --cygnus.
# Also check that TEXINFOS + cygnus work without requiring the
# '-Wno-override' option.
# See also sister test txinfo5b.sh.
# Report from Ian Taylor.

. ./defs || exit 1

cat >> configure.ac << 'END'
AM_MAINTAINER_MODE
END

cat > Makefile.am << 'END'
info_TEXINFOS = ian.texi
END

echo '@setfilename ian.info' > ian.texi

$ACLOCAL
$AUTOMAKE --cygnus -Wno-obsolete

:
