#! /bin/sh
# Copyright (C) 2005-2012 Free Software Foundation, Inc.
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

# Make sure 'missing texinfo' does not create empty files.
# Report from Bob Proulx.

. ./defs || exit 1

echo info_TEXINFOS = bar.texi >Makefile.am
echo grepme >bar.info
$sleep
cat >bar.texi <<EOF
@setfilename bar.info
EOF

echo AC_OUTPUT >>configure.ac

cat >makeinfo <<\EOF
#!/bin/sh
# This script
# 1. fails so 'missing' can take over
# 2. does not understand '--version' so 'missing' thinks 'makeinfo' isn't
#    installed
exec false
EOF

chmod +x makeinfo

PATH=$(pwd)$PATH_SEPARATOR$PATH
export PATH

# Otherwise configure might pick up a working makeinfo from the
# environment.  Seen in automake bug#10866.
unset MAKEINFO || :

$ACLOCAL
$AUTOCONF
$AUTOMAKE --add-missing

./configure
$MAKE
grep grepme bar.info
test -f bar.info

# We should not create a missing bar.info.
rm -f bar.info
$MAKE && exit 1
test ! -e bar.info

:
