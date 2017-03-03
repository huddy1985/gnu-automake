#! /bin/sh
# Copyright (C) 2007-2012 Free Software Foundation, Inc.
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

# Test to make sure pkgdatadir can be overridden via AC_SUBST.

. ./defs || Exit 1

cat >>configure.ac <<'EOF'
AC_SUBST([pkgdatadir], ["FOO"])
AC_OUTPUT
EOF

cat > Makefile.am << 'EOF'
showme:
	@echo $(pkgdatadir)
EOF

$ACLOCAL
$AUTOCONF
$AUTOMAKE
./configure
$MAKE showme | grep FOO
