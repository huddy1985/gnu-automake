#! /bin/sh
# Copyright (C) 2009-2012 Free Software Foundation, Inc.
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

# If $(pythondir) is the empty string, then nothing should be installed there.

required=python
. ./defs || Exit 1

cat >>configure.ac <<'END'
AM_PATH_PYTHON
AC_OUTPUT
END

mkdir sub

cat >Makefile.am <<'END'
python_PYTHON = one.py
END

cat >one.py <<'END'
def one(): return 1
END

$ACLOCAL
$AUTOCONF
$AUTOMAKE --add-missing

instdir=`pwd`/inst
destdir=`pwd`/dest
mkdir build
cd build
../configure --prefix="$instdir"
$MAKE

pythondir=
export pythondir

$MAKE -e install
test ! -d "$instdir"
$MAKE -e install DESTDIR="$destdir"
test ! -d "$instdir"
test ! -d "$destdir"
$MAKE -e uninstall > stdout || { cat stdout; Exit 1; }
cat stdout
grep 'rm -f' stdout && Exit 1
$MAKE -e uninstall DESTDIR="$destdir"

:
