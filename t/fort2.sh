#! /bin/sh
# Copyright (C) 2006-2012 Free Software Foundation, Inc.
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

# Test that AC_FC_SRCEXT(f9x) works as intended:
# - $(FCFLAGS_f) will be used

# Cf. fort1.test and link_f90_only.test.

. ./defs || exit 1

mkdir sub

cat >>configure.ac <<'END'
AC_PROG_FC
AC_FC_SRCEXT([f90])
AC_FC_SRCEXT([f95])
AC_FC_SRCEXT([f03])
AC_FC_SRCEXT([f08])
AC_FC_SRCEXT([blabla])
END

cat >Makefile.am <<'END'
bin_PROGRAMS = hello goodbye
hello_SOURCES = hello.f90 foo.f95 sub/bar.f95 hi.f03 sub/howdy.f03 greets.f08 sub/bonjour.f08
goodbye_SOURCES = bye.f95 sub/baz.f90
goodbye_FCFLAGS =
END

$ACLOCAL
$AUTOMAKE
# The following tests aren't fool-proof, but they don't
# need a Fortran compiler.
grep '.\$(LINK)'       Makefile.in && exit 1
grep '.\$(FCLINK)'     Makefile.in
grep '.\$(FCCOMPILE)'  Makefile.in > stdout
cat stdout
grep -v '\$(FCFLAGS_f' stdout && exit 1
grep '.\$(FC.*\$(FCFLAGS_blabla' Makefile.in && exit 1
# Notice the TAB:
grep '^[	].*\$(FC.*\$(FCFLAGS_f90).*\.f90' Makefile.in
grep '^[	].*\$(FC.*\$(FCFLAGS_f95).*\.f95' Makefile.in
grep '^[	].*\$(FC.*\$(FCFLAGS_f03).*\.f03' Makefile.in
grep '^[	].*\$(FC.*\$(FCFLAGS_f08).*\.f08' Makefile.in
grep '^[	].*\$(FC.*\$(FCFLAGS_f90).*\.f95' Makefile.in && exit 1
grep '^[	].*\$(FC.*\$(FCFLAGS_f95).*\.f90' Makefile.in && exit 1
grep '^[	].*\$(FC.*\$(FCFLAGS_f90).*\.f03' Makefile.in && exit 1
grep '^[	].*\$(FC.*\$(FCFLAGS_f08).*\.f90' Makefile.in && exit 1

:
