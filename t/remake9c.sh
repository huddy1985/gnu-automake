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

# Test remake rules when acinclude.m4 or its prerequisites change.
# Keep in sync with the other sister tests 'remake9*.test'.

. ./defs || Exit 1

magic1=::MagicStringOne::
magic2=__MagicStringTwo__

if using_gmake; then
  remake_() { $MAKE nil; }
else
  remake_() { $MAKE Makefile && $MAKE foo.sh; }
fi

cat >> configure.ac <<END
FINGERPRINT='my_fingerprint'
AC_SUBST([FINGERPRINT])
AC_CONFIG_FILES([foo.sh:foo.in], [chmod a+x foo.sh])
AC_OUTPUT
END

cat > Makefile.am <<'END'
nil:
.PHONY: nil

# The right way to extend an autogenerated aclocal.m4 is to provide
# an acinclude.m4 file.
$(srcdir)/acinclude.m4: $(srcdir)/tweak-acinclude-m4
	$(SHELL) $(srcdir)/tweak-acinclude-m4 <$@ >$@-t
	mv -f $@-t $@
	touch $@
EXTRA_DIST = $(srcdir)/tweak-acinclude-m4

# Used by "make distcheck" later.
check-local:
	test x'$(FINGERPRINT)' = x'DummyValue'
	test x"`./foo.sh`" = x"DummyValue"
END

cat > foo.in <<END
#!/bin/sh
echo '@FINGERPRINT@'
END

echo "AC_DEFUN([my_fingerprint], [BadBadBad])" > acinclude.m4

echo : > tweak-acinclude-m4 # It is a no-op by default.

$ACLOCAL
$AUTOCONF
$AUTOMAKE

for vpath in : false; do

  if $vpath; then
    mkdir build
    cd build
    srcdir=..
  else
    srcdir=.
  fi

  $srcdir/configure
  $MAKE # Should be a no-op.

  $sleep
  echo "AC_DEFUN([my_fingerprint], [$magic1])" > $srcdir/acinclude.m4
  remake_
  $FGREP FINGERPRINT Makefile # For debugging.
  $FGREP $magic1 Makefile
  test x"`./foo.sh`" = x"$magic1"

  $sleep
  echo "echo 'AC_DEFUN([my_fingerprint], [$magic2])'" \
    > $srcdir/tweak-acinclude-m4
  remake_
  $FGREP FINGERPRINT Makefile # For debugging.
  $FGREP $magic1 Makefile && Exit 1
  $FGREP $magic2 Makefile
  test x"`./foo.sh`" = x"$magic2"

  $sleep
  echo : > $srcdir/tweak-acinclude-m4 # Make it a no-op again.
  echo "AC_DEFUN([my_fingerprint], [DummyValue])" > $srcdir/acinclude.m4
  using_gmake || remake_
  $MAKE distcheck
  $FGREP $magic1 Makefile && Exit 1 # Sanity check.
  $FGREP $magic2 Makefile && Exit 1 # Likewise.

  $MAKE distclean

  cd $srcdir

done

:
