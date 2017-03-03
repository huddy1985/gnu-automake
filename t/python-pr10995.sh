#! /bin/sh
# Copyright (C) 2012 Free Software Foundation, Inc.
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

# Test automake bug#10995: am__py_compile doesn't get correctly defined
# when there a 'noinst_PYTHON' declaration precedes a 'foo_PYTHON'
# declaration.

required=python
. ./defs || Exit 1

cat >> configure.ac <<'EOF'
AM_PATH_PYTHON
AC_OUTPUT
EOF

cat > Makefile.am <<'END'
yesinstdir = $(prefix)/py
noinst_PYTHON = no.py
yesinst_PYTHON = yes.py
disttest: distdir
	test -f $(distdir)/no.py
	test -f $(distdir)/yes.py
END

echo 'def foo(): return 1' > yes.py
# no.py shouldn't be byte-compiled, so lets make it syntactically invalid.
echo 'if' > no.py

$ACLOCAL
$AUTOCONF
$AUTOMAKE --add-missing
test -f py-compile

inst=`pwd`/inst

./configure --prefix="$inst"
$MAKE install
test -f "$inst/py/yes.py"
test -f "$inst/py/yes.pyc"
test ! -f "$inst/py/no.py"
test ! -f "$inst/py/no.pyc"

$MAKE disttest

:
