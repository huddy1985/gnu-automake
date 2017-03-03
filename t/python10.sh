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

# Test _PYTHON with conditionals.

required=python
. ./defs || exit 1

cat >>configure.ac <<'EOF'
AM_PATH_PYTHON
AM_CONDITIONAL([ONE], [test "x$one" = x1])
AC_OUTPUT
EOF

cat > Makefile.am <<'END'
if ONE
mydir=$(prefix)/my
my_PYTHON = one.py
else
yourdir=$(prefix)/your
your_PYTHON = two.py
endif

one.py:
	echo 'def one(): return 1' >$@
two.py:
	echo 'def two(): return 1' >$@

.PHONY: disttest
disttest: distdir
	ls -l $(distdir)
	test -f $(distdir)/one.py
	test -f $(distdir)/two.py
END

$ACLOCAL
$AUTOCONF
$AUTOMAKE --add-missing

inst=inst_
mkdir inst_ build_
cd build_

cwd=$(pwd) || fatal_ "getting current working directory"

../configure --prefix="$cwd/$inst" one=0
$MAKE install
test -f "$inst/your/two.py"
test -f "$inst/your/two.pyc"
test -f "$inst/your/two.pyo"
test ! -e "$inst/my/one.py"
test ! -e "$inst/my/one.pyc"
test ! -e "$inst/my/one.pyo"
$MAKE uninstall
test ! -e "$inst/your/two.py"
test ! -e "$inst/your/two.pyc"
test ! -e "$inst/your/two.pyo"

../configure --prefix=$cwd/"$inst" one=1
$MAKE install
test ! -e "$inst/your/two.py"
test ! -e "$inst/your/two.pyc"
test ! -e "$inst/your/two.pyo"
test -f "$inst/my/one.py"
test -f "$inst/my/one.pyc"
test -f "$inst/my/one.pyo"
$MAKE uninstall
test ! -e "$inst/my/one.py"
test ! -e "$inst/my/one.pyc"
test ! -e "$inst/my/one.pyo"

$MAKE disttest

:
