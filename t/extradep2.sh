#! /bin/sh
# Copyright (C) 2010-2012 Free Software Foundation, Inc.
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

# Test EXTRA_*_DEPENDENCIES, libtool version; see extradep.test.

required='cc libtoolize'
. ./defs || Exit 1

cat >> configure.ac << 'END'
AC_PROG_CC
AM_PROG_AR
AC_PROG_LIBTOOL
AC_SUBST([deps], [bardep])
AC_OUTPUT
END

cat > Makefile.am << 'END'
noinst_LTLIBRARIES = libfoo.la
EXTRA_libfoo_la_DEPENDENCIES = libfoodep
libfoodep:
	@echo making $@
	@: > $@
CLEANFILES = libfoodep

bin_PROGRAMS = bar
bar_LDADD = libfoo.la
EXTRA_bar_DEPENDENCIES = $(deps)

EXTRA_DIST = bardep

.PHONY: bar-has-been-updated
bar-has-been-updated:
	stat older bar$(EXEEXT) libfoo.la || : For debugging.
	test `ls -t bar$(EXEEXT) older | sed q` = bar$(EXEEXT)
END

cat >libfoo.c <<'END'
int libfoo () { return 0; }
END

cat >bar.c <<'END'
extern int libfoo ();
int main () { return libfoo (); }
END

libtoolize
$ACLOCAL
$AUTOMAKE --add-missing
$AUTOCONF

./configure

# Hypothesis: EXTRA_*_DEPENDENCIES are honored.

: >foodep
: >foodep2
: >bardep
$MAKE >stdout || { cat stdout; Exit 1; }
cat stdout
grep 'making libfoodep' stdout

rm -f bardep
$MAKE && Exit 1
: >bardep

$MAKE
: > older
$sleep
touch libfoo.la
$MAKE
$MAKE bar-has-been-updated

$MAKE distcheck

:
