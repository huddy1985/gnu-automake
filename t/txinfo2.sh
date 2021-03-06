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

# Test to ensure that a ".info~" file doesn't end up in the
# distribution.  Bug report from Greg McGary.

. test-init.sh

cat >> configure.ac << 'END'
AC_OUTPUT
END

cat > Makefile.am << 'END'
info_TEXINFOS = textutils.texi
.PHONY: test
test:
	@echo DISTFILES = $(DISTFILES)
	case '$(DISTFILES)' in *'~'*) exit 1;; *) exit 0;; esac
END

: > texinfo.tex
echo '@setfilename textutils.info' > textutils.texi
: > textutils.info~

$ACLOCAL
$AUTOCONF
$AUTOMAKE

./configure
$MAKE test

:
