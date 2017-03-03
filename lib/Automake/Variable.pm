# Copyright (C) 2003, 2004  Free Software Foundation, Inc.

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
# 02111-1307, USA.

package Automake::Variable;
use strict;
use Carp;

use Automake::Channels;
use Automake::ChannelDefs;
use Automake::Configure_ac;
use Automake::Item;
use Automake::VarDef;
use Automake::Condition qw (TRUE FALSE);
use Automake::DisjConditions;
use Automake::General 'uniq';
use Automake::Wrap 'makefile_wrap';

require Exporter;
use vars '@ISA', '@EXPORT', '@EXPORT_OK';
@ISA = qw/Automake::Item Exporter/;
@EXPORT = qw (err_var msg_var msg_cond_var reject_var
	      var rvar vardef rvardef
	      variables
	      scan_variable_expansions check_variable_expansions
	      variable_delete
	      variables_dump
	      set_seen
	      require_variables
	      variable_value
	      output_variables
	      transform_variable_recursively);

=head1 NAME

Automake::Variable - support for variable definitions

=head1 SYNOPSIS

  use Automake::Variable;
  use Automake::VarDef;

  # Defining a variable.
  Automake::Variable::define($varname, $owner, $type,
                             $cond, $value, $comment,
                             $where, $pretty)

  # Looking up a variable.
  my $var = var $varname;
  if ($var)
    {
      ...
    }

  # Looking up a variable that is assumed to exist.
  my $var = rvar $varname;

  # The list of conditions where $var has been defined.
  # ($var->conditions is an Automake::DisjConditions,
  # $var->conditions->conds is a list of Automake::Condition.)
  my @conds = $var->conditions->conds

  # Accessing to the definition in Condition $cond.
  # $def is an Automake::VarDef.
  my $def = $var->def ($cond);
  if ($def)
    {
      ...
    }

  # When the conditional definition is assumed to exist, use
  my $def = $var->rdef ($cond);


=head1 DESCRIPTION

This package provides support for Makefile variable definitions.

An C<Automake::Variable> is a variable name associated to possibly
many conditional definitions.  These definitions are instances
of C<Automake::VarDef>.

Therefore obtaining the value of a variable under a given
condition involves two lookups.  One to look up the variable,
and one to look up the conditional definition:

  my $var = var $name;
  if ($var)
    {
      my $def = $var->def ($cond);
      if ($def)
        {
          return $def->value;
        }
      ...
    }
  ...

When it is known that the variable and the definition
being looked up exist, the above can be simplified to

  return var ($name)->def ($cond)->value; # Do not write this.

but is better written

  return rvar ($name)->rdef ($cond)->value;

or even

  return rvardef ($name, $cond)->value;

The I<r> variants of the C<var>, C<def>, and C<vardef> methods add an
extra test to ensure that the lookup succeeded, and will diagnose
failures as internal errors (with a message which is much more
informative than Perl's warning about calling a method on a
non-object).

=cut

my $_VARIABLE_PATTERN = '^[.A-Za-z0-9_@]+' . "\$";

# The order in which variables should be output.  (May contain
# duplicates -- only the first occurrence matters.)
my @_var_order;

# This keeps track of all variables defined by &_gen_varname.
# $_gen_varname{$base} is a hash for all variable defined with
# prefix `$base'.  Values stored this this hash are the variable names.
# Keys have the form "(COND1)VAL1(COND2)VAL2..." where VAL1 and VAL2
# are the values of the variable for condition COND1 and COND2.
my %_gen_varname = ();

# Declare the macros that define known variables, so we can
# hint the user if she try to use one of these variables.

# Macros accessible via aclocal.
my %_am_macro_for_var =
  (
   ANSI2KNR => 'AM_C_PROTOTYPES',
   CCAS => 'AM_PROG_AS',
   CCASFLAGS => 'AM_PROG_AS',
   EMACS => 'AM_PATH_LISPDIR',
   GCJ => 'AM_PROG_GCJ',
   LEX => 'AM_PROG_LEX',
   LIBTOOL => 'AC_PROG_LIBTOOL',
   lispdir => 'AM_PATH_LISPDIR',
   pkgpyexecdir => 'AM_PATH_PYTHON',
   pkgpythondir => 'AM_PATH_PYTHON',
   pyexecdir => 'AM_PATH_PYTHON',
   PYTHON => 'AM_PATH_PYTHON',
   pythondir => 'AM_PATH_PYTHON',
   U => 'AM_C_PROTOTYPES',
   );

# Macros shipped with Autoconf.
my %_ac_macro_for_var =
  (
   ALLOCA => 'AC_FUNC_ALLOCA',
   CC => 'AC_PROG_CC',
   CFLAGS => 'AC_PROG_CC',
   CXX => 'AC_PROG_CXX',
   CXXFLAGS => 'AC_PROG_CXX',
   F77 => 'AC_PROG_F77',
   F77FLAGS => 'AC_PROG_F77',
   RANLIB => 'AC_PROG_RANLIB',
   YACC => 'AC_PROG_YACC',
   );

# The name of the configure.ac file.
my $configure_ac = find_configure_ac;

# Variables that can be overriden without complaint from -Woverride
my %_silent_variable_override =
  (AM_MAKEINFOHTMLFLAGS => 1,
   AR => 1,
   ARFLAGS => 1,
   DEJATOOL => 1,
   JAVAC => 1);

# This hash records helper variables used to implement conditional '+='.
# Keys have the form "VAR:CONDITIONS".  The value associated to a key is
# the named of the helper variable used to append to VAR in CONDITIONS.
my %_appendvar = ();

# Each call to C<Automake::Variable::traverse_recursively> gets an
# unique label. This is used to detect recursively defined variables.
my $_traversal = 0;


=head2 Error reporting functions

In these functions, C<$var> can be either a variable name, or
an instance of C<Automake::Variable>.

=over 4

=item C<err_var ($var, $message, [%options])>

Uncategorized errors about variables.

=cut

sub err_var ($$;%)
{
  msg_var ('error', @_);
}

=item C<msg_cond_var ($channel, $cond, $var, $message, [%options])>

Messages about conditional variable.

=cut

sub msg_cond_var ($$$$;%)
{
  my ($channel, $cond, $var, $msg, %opts) = @_;
  my $v = ref ($var) ? $var : rvar ($var);
  msg $channel, $v->rdef ($cond)->location, $msg, %opts;
}

=item C<msg_var ($channel, $var, $message, [%options])>

Messages about variables.

=cut

sub msg_var ($$$;%)
{
  my ($channel, $var, $msg, %opts) = @_;
  my $v = ref ($var) ? $var : rvar ($var);
  # Don't know which condition is concerned.  Pick any.
  my $cond = $v->conditions->one_cond;
  msg_cond_var $channel, $cond, $v, $msg, %opts;
}

=item C<$bool = reject_var ($varname, $error_msg)>

Bail out with C<$error_msg> if a variable with name C<$varname> has
been defined.

Return true iff C<$varname> is defined.

=cut

sub reject_var ($$)
{
  my ($var, $msg) = @_;
  my $v = var ($var);
  if ($v)
    {
      err_var $v, $msg;
      return 1;
    }
  return 0;
}

=back

=head2 Administrative functions

=over 4

=item C<Automake::Variable::hook ($varname, $fun)>

Declare a function to be called whenever a variable
named C<$varname> is defined or redefined.

C<$fun> should take two arguments: C<$type> and C<$value>.
When type is C<''> or <':'>, C<$value> is the value being
assigned to C<$varname>.  When C<$type> is C<'+'>, C<$value>
is the value being appended to  C<$varname>.

=cut

use vars '%_hooks';
sub hook ($$)
{
  my ($var, $fun) = @_;
  $_hooks{$var} = $fun;
}

=item C<variables>

Returns the list of all L<Automake::Variable> instances.  (I.e., all
variables defined so far.)

=cut

use vars '%_variable_dict';
sub variables ()
{
  return values %_variable_dict;
}

=item C<Automake::Variable::reset>

The I<forget all> function.  Clears all know variables and reset some
other internal data.

=cut

sub reset ()
{
  %_variable_dict = ();
  %_appendvar = ();
  @_var_order = ();
  %_gen_varname = ();
  $_traversal = 0;
}

=item C<var ($varname)>

Return the C<Automake::Variable> object for the variable
named C<$varname> if defined.   Return 0 otherwise.

=cut

sub var ($)
{
  my ($name) = @_;
  return $_variable_dict{$name} if exists $_variable_dict{$name};
  return 0;
}

=item C<vardef ($varname, $cond)>

Return the C<Automake::VarDef> object for the variable named
C<$varname> if defined in condition C<$cond>.  Return false
if the condition or the variable does not exist.

=cut

sub vardef ($$)
{
  my ($name, $cond) = @_;
  my $var = var $name;
  return $var && $var->def ($cond);
}

# Create the variable if it does not exist.
# This is used only by other functions in this package.
sub _cvar ($)
{
  my ($name) = @_;
  my $v = var $name;
  return $v if $v;
  return _new Automake::Variable $name;
}

=item C<rvar ($varname)>

Return the C<Automake::Variable> object for the variable named
C<$varname>.  Abort with an internal error if the variable was not
defined.

The I<r> in front of C<var> stands for I<required>.  One
should call C<rvar> to assert the variable's existence.

=cut

sub rvar ($)
{
  my ($name) = @_;
  my $v = var $name;
  prog_error ("undefined variable $name\n" . &variables_dump)
    unless $v;
  return $v;
}

=item C<rvardef ($varname, $cond)>

Return the C<Automake::VarDef> object for the variable named
C<$varname> if defined in condition C<$cond>.  Abort with an internal
error if the condition or the variable does not exist.

=cut

sub rvardef ($$)
{
  my ($name, $cond) = @_;
  return rvar ($name)->rdef ($cond);
}

=back

=head2 Methods

C<Automake::Variable> is a subclass of C<Automake::Item>.  See
that package for inherited methods.

Here are the methods specific to the C<Automake::Variable> instances.
Use the C<define> function, described latter, to create such objects.

=over 4

=cut

# Create Automake::Variable objects.  This is used
# only in this file.  Other users should use
# the "define" function.
sub _new ($$)
{
  my ($class, $name) = @_;
  my $self = Automake::Item::new ($class, $name);
  $self->{'scanned'} = 0;
  $_variable_dict{$name} = $self;
  return $self;
}

# _check_ambiguous_condition ($SELF, $COND, $WHERE)
# -------------------------------------------------
# Check for an ambiguous conditional.  This is called when a variable
# is being defined conditionally.  If we already know about a
# definition that is true under the same conditions, then we have an
# ambiguity.
sub _check_ambiguous_condition ($$$)
{
  my ($self, $cond, $where) = @_;
  my $var = $self->name;
  my ($message, $ambig_cond) = $self->conditions->ambiguous_p ($var, $cond);

  # We allow silent variables to be overridden silently.
  my $def = $self->def ($cond);
  if ($message && !($def && $def->pretty == VAR_SILENT))
    {
      msg 'syntax', $where, "$message ...", partial => 1;
      msg_var ('syntax', $var, "... `$var' previously defined here");
      verb ($self->dump);
    }
}

=item C<$bool = $var-E<gt>check_defined_unconditionally ([$parent, $parent_cond])>

Warn if the variable is conditionally defined.  C<$parent> is the name
of the parent variable, and C<$parent_cond> the condition of the parent
definition.  These two variables are used to display diagnostics.

=cut

sub check_defined_unconditionally ($;$$)
{
  my ($self, $parent, $parent_cond) = @_;

  if (!$self->conditions->true)
    {
      if ($parent)
	{
	  msg_cond_var ('unsupported', $parent_cond, $parent,
			"automake does not support conditional definition of "
			. $self->name . " in $parent");
	}
      else
	{
	  msg_var ('unsupported', $self,
		   "automake does not support " . $self->name
		   . " being defined conditionally");
	}
    }
}

=item C<$str = $var-E<gt>output ([@conds])>

Format all the definitions of C<$var> if C<@cond> is not specified,
else only that corresponding to C<@cond>.

=cut

sub output ($@)
{
  my ($self, @conds) = @_;

  @conds = $self->conditions->conds
    unless @conds;

  my $res = '';
  my $name = $self->name;

  foreach my $cond (@conds)
    {
      my $def = $self->def ($cond);
      prog_error ("unknown condition `" . $cond->human . "' for `"
		  . $self->name . "'")
	unless $def;

      next
	if $def->pretty == VAR_SILENT;

      $res .= $def->comment;

      my $val = $def->raw_value;
      my $equals = $def->type eq ':' ? ':=' : '=';
      my $str = $cond->subst_string;


      if ($def->pretty == VAR_ASIS)
	{
	  my $output_var = "$name $equals $val";
	  $output_var =~ s/^/$str/meg;
	  $res .= "$output_var\n";
	}
      elsif ($def->pretty == VAR_PRETTY)
	{
	  # Suppress escaped new lines.  &makefile_wrap will
	  # add them back, maybe at other places.
	  $val =~ s/\\$//mg;
	  my $wrap = makefile_wrap ("$str$name $equals", "$str\t",
				    split (' ', $val));

	  # If the last line of the definition is made only of
	  # @substitutions@, append an empty variable to make sure it
	  # cannot be substituted as a blank line (that would confuse
	  # HP-UX Make).
	  $wrap = makefile_wrap ("$str$name $equals", "$str\t",
				 split (' ', $val), '$(am__empty)')
	    if $wrap =~ /\n(\s*@\w+@)+\s*$/;

	  $res .= $wrap;
	}
      else # ($def->pretty == VAR_SORTED)
	{
	  # Suppress escaped new lines.  &makefile_wrap will
	  # add them back, maybe at other places.
	  $val =~ s/\\$//mg;
	  $res .= makefile_wrap ("$str$name $equals", "$str\t",
				 sort (split (' ' , $val)));
	}
    }
  return $res;
}

=item C<@values = $var-E<gt>value_as_list ($cond, [$parent, $parent_cond])>

Get the value of C<$var> as a list, given a specified condition,
without recursing through any subvariables.

C<$cond> is the condition of interest.  C<$var> does not need
to be defined for condition C<$cond> exactly, but it needs
to be defined for at most one condition implied by C<$cond>.

C<$parent> and C<$parent_cond> designate the name and the condition
of the parent variable, i.e., the variable in which C<$var> is
being expanded.  These are used in diagnostics.

For example, if C<A> is defined as "C<foo $(B) bar>" in condition
C<TRUE>, calling C<rvar ('A')->value_as_list (TRUE)> will return
C<("foo", "$(B)", "bar")>.

=cut

sub value_as_list ($$;$$)
{
  my ($self, $cond, $parent, $parent_cond) = @_;
  my @result;

  # Get value for given condition
  my $onceflag;
  foreach my $vcond ($self->conditions->conds)
    {
      if ($vcond->true_when ($cond))
	{
	  # If there is more than one definitions of $var matching
	  # $cond then we are in trouble: tell the user we need a
	  # paddle.  Continue by merging results from all conditions,
	  # although it doesn't make much sense.
	  $self->check_defined_unconditionally ($parent, $parent_cond)
	    if $onceflag;
	  $onceflag = 1;

	  my $val = $self->rdef ($vcond)->value;
	  push @result, split (' ', $val);
	}
    }
  return @result;
}

=item C<@values = $var-E<gt>value_as_list_recursive ([%options])>

Return the contents of C<$var> as a list, split on whitespace.  This
will recursively follow C<$(...)> and C<${...}> inclusions.  It
preserves C<@...@> substitutions.

C<%options> is a list of option for C<Variable::traverse_recursively>
(see this method).  The most useful is C<cond_filter>:

  $var->value_as_list_recursive (cond_filter => $cond)

will return the contents of C<$var> and any subvariable in all
conditions implied by C<$cond>.

C<%options> can also carry options specific to C<value_as_list_recursive>.
Presently, the only such option is C<location =E<gt> 1> which instructs
C<value_as_list_recursive> to return a list of C<[$location, @values]> pairs.

=cut

sub value_as_list_recursive ($;%)
{
  my ($var, %options) = @_;

  return $var->traverse_recursively
    (# Construct [$location, $value] pairs if requested.
     sub {
       my ($var, $val, $cond, $full_cond) = @_;
       return [$var->rdef ($cond)->location, $val] if $options{'location'};
       return $val;
     },
     # Collect results.
     sub {
       my ($var, $parent_cond, @allresults) = @_;
       return map { my ($cond, @vals) = @$_; @vals } @allresults;
     },
     %options);
}


=item C<$bool = $var-E<gt>has_conditional_contents>

Return 1 if C<$var> or one of its subvariable was conditionally
defined.  Return 0 otherwise.

=cut

sub has_conditional_contents ($)
{
  my ($self) = @_;

  # Traverse the variable recursively until we
  # find a variable defined conditionally.
  # Use `die' to abort the traversal, and pass it `$full_cond'
  # to we can find easily whether the `eval' block aborted
  # because we found a condition, or for some other error.
  eval
    {
      $self->traverse_recursively
	(sub
	 {
	   my ($subvar, $val, $cond, $full_cond) = @_;
	   die $full_cond if ! $full_cond->true;
	   return ();
	 },
	 sub { return (); });
    };
  if ($@)
    {
      return 1 if ref ($@) && $@->isa ("Automake::Condition");
      # Propagate other errors.
      die;
    }
  return 0;
}


=item C<$string = $var-E<gt>dump>

Return a string describing all we know about C<$var>.
For debugging.

=cut

sub dump ($)
{
  my ($self) = @_;

  my $text = $self->name . ": \n  {\n";
  foreach my $vcond ($self->conditions->conds)
    {
      $text .= "    " . $vcond->human . " => " . $self->rdef ($vcond)->dump;
    }
  $text .= "  }\n";
  return $text;
}


=back

=head2 Utility functions

=over 4

=item C<@list = scan_variable_expansions ($text)>

Return the list of variable names expanded in C<$text>.  Note that
unlike some other functions, C<$text> is not split on spaces before we
check for subvariables.

=cut

sub scan_variable_expansions ($)
{
  my ($text) = @_;
  my @result = ();

  # Strip comments.
  $text =~ s/#.*$//;

  # Record each use of ${stuff} or $(stuff) that does not follow a $.
  while ($text =~ /(?<!\$)\$(?:\{([^\}]*)\}|\(([^\)]*)\))/g)
    {
      my $var = $1 || $2;
      # The occurence may look like $(string1[:subst1=[subst2]]) but
      # we want only `string1'.
      $var =~ s/:[^:=]*=[^=]*$//;
      push @result, $var;
    }

  return @result;
}

=item C<check_variable_expansions ($text, $where)>

Check variable expansions in C<$text> and warn about any name that
does not conform to POSIX.  C<$where> is the location of C<$text>
for the error message.

=cut

sub check_variable_expansions ($$)
{
  my ($text, $where) = @_;
  # Catch expansion of variables whose name does not conform to POSIX.
  foreach my $var (scan_variable_expansions ($text))
    {
      if ($var !~ /$_VARIABLE_PATTERN/o)
	{
	  # If the variable name contains a space, it's likely
	  # to be a GNU make extension (such as $(addsuffix ...)).
	  # Mention this in the diagnostic.
	  my $gnuext = "";
	  $gnuext = "\n(probably a GNU make extension)" if $var =~ / /;
	  msg ('portability', $where,
	       "$var: non-POSIX variable name$gnuext");
	}
    }
}



=item C<Automake::Variable::define($varname, $owner, $type, $cond, $value, $comment, $where, $pretty)>

Define or append to a new variable.

C<$varname>: the name of the variable being defined.

C<$owner>: owner of the variable (one of C<VAR_MAKEFILE>,
C<VAR_CONFIGURE>, or C<VAR_AUTOMAKE>, defined by L<Automake::VarDef>).
Variables can be overriden, provided the new owner is not weaker
(C<VAR_AUTOMAKE> < C<VAR_CONFIGURE> < C<VAR_MAKEFILE>).

C<$type>: the type of the assignment (C<''> for C<FOO = bar>,
C<':'> for C<FOO := bar>, and C<'+'> for C<'FOO += bar'>).

C<$cond>: the C<Condition> in which C<$var> is being defined.

C<$value>: the value assigned to C<$var> in condition C<$cond>.

C<$comment>: any comment (C<'# bla.'>) associated with the assignment.
Comments from C<+=> assignments stack with comments from the last C<=>
assignment.

C<$where>: the C<Location> of the assignment.

C<$pretty>: whether C<$value> should be pretty printed (one of
C<VAR_ASIS>, C<VAR_PRETTY>, C<VAR_SILENT>, or C<VAR_SORTED>, defined
by by L<Automake::VarDef>).  C<$pretty> applies only to real
assignments.  I.e., it does not apply to a C<+=> assignment (except
when part of it is being done as a conditional C<=> assignment).

This function will all run any hook registered with the C<hook>
function.

=cut

sub define ($$$$$$$$)
{
  my ($var, $owner, $type, $cond, $value, $comment, $where, $pretty) = @_;

  prog_error "$cond is not a reference"
    unless ref $where;

  prog_error "$where is not a reference"
    unless ref $where;

  prog_error "pretty argument missing"
    unless defined $pretty && ($pretty == VAR_ASIS
			       || $pretty == VAR_PRETTY
			       || $pretty == VAR_SILENT
			       || $pretty == VAR_SORTED);

  error $where, "bad characters in variable name `$var'"
    if $var !~ /$_VARIABLE_PATTERN/o;

  # `:='-style assignments are not acknowledged by POSIX.  Moreover it
  # has multiple meanings.  In GNU make or BSD make it means "assign
  # with immediate expansion", while in OSF make it is used for
  # conditional assignments.
  msg ('portability', $where, "`:='-style assignments are not portable")
    if $type eq ':';

  check_variable_expansions ($value, $where);

  # If there's a comment, make sure it is \n-terminated.
  if ($comment)
    {
      chomp $comment;
      $comment .= "\n";
    }
  else
    {
      $comment = '';
    }

  my $self = _cvar $var;

  my $def = $self->def ($cond);
  my $new_var = $def ? 0 : 1;

  # Additional checks for Automake definitions.
  if ($owner == VAR_AUTOMAKE && ! $new_var)
    {
      # An Automake variable must be consistently defined with the same
      # sign by Automake.
      if ($def->type ne $type && $def->owner == VAR_AUTOMAKE)
	{
	  error ($def->location,
		 "Automake variable `$var' was set with `"
		 . $def->type . "=' here...", partial => 1);
	  error ($where, "... and is now set with `$type=' here.");
	  prog_error ("Automake variable assignments should be consistently\n"
		      . "defined with the same sign.");
	}

      # If Automake tries to override a value specified by the user,
      # just don't let it do.
      if ($def->owner != VAR_AUTOMAKE)
	{
	  if (! exists $_silent_variable_override{$var})
	    {
	      my $condmsg = ($cond == TRUE
			     ? '' : (" in condition `" . $cond->human . "'"));
	      msg_cond_var ('override', $cond, $var,
			    "user variable `$var' defined here$condmsg...",
			    partial => 1);
	      msg ('override', $where,
		   "... overrides Automake variable `$var' defined here");
	    }
	  verb ("refusing to override the user definition of:\n"
		. $self->dump ."with `" . $cond->human . "' => `$value'");
	  return;
	}
    }

  # Differentiate assignment types.

  # 1. append (+=) to a variable defined for current condition
  if ($type eq '+' && ! $new_var)
    {
      $def->append ($value, $comment);

      # Only increase owners.  A VAR_CONFIGURE variable augmented in a
      # Makefile.am becomes a VAR_MAKEFILE variable.
      $def->set_owner ($owner, $where->clone)
	if $owner > $def->owner;
    }
  # 2. append (+=) to a variable defined for *another* condition
  elsif ($type eq '+' && ! $self->conditions->false)
    {
      # * Generally, $cond is not TRUE.  For instance:
      #     FOO = foo
      #     if COND
      #       FOO += bar
      #     endif
      #   In this case, we declare an helper variable conditionally,
      #   and append it to FOO:
      #     FOO = foo $(am__append_1)
      #     @COND_TRUE@am__append_1 = bar
      #   Of course if FOO is defined under several conditions, we add
      #   $(am__append_1) to each definitions.
      #
      # * If $cond is TRUE, we don't need the helper variable.  E.g., in
      #     if COND1
      #       FOO = foo1
      #     else
      #       FOO = foo2
      #     endif
      #     FOO += bar
      #   we can add bar directly to all definition of FOO, and output
      #     @COND_TRUE@FOO = foo1 bar
      #     @COND_FALSE@FOO = foo2 bar

      # Do we need an helper variable?
      if ($cond != TRUE)
        {
	    # Does the helper variable already exists?
	    my $key = "$var:" . $cond->string;
	    if (exists $_appendvar{$key})
	      {
		# Yes, let's simply append to it.
		$var = $_appendvar{$key};
		$owner = VAR_AUTOMAKE;
		$self = var ($var);
		$def = $self->rdef ($cond);
		$new_var = 0;
	      }
	    else
	      {
		# No, create it.
		my $num = 1 + keys (%_appendvar);
		my $hvar = "am__append_$num";
		$_appendvar{$key} = $hvar;
		&define ($hvar, VAR_AUTOMAKE, '+',
			 $cond, $value, $comment, $where, $pretty);
		# Now HVAR is to be added to VAR.
		$comment = '';
		$value = "\$($hvar)";
	      }
	}

      # Add VALUE to all definitions of SELF.
      foreach my $vcond ($self->conditions->conds)
        {
	  # We have a bit of error detection to do here.
	  # This:
	  #   if COND1
	  #     X = Y
	  #   endif
	  #   X += Z
	  # should be rejected because X is not defined for all conditions
	  # where `+=' applies.
	  my $undef_cond = $self->not_always_defined_in_cond ($cond);
	  if (! $undef_cond->false)
	    {
	      error ($where,
		     "Cannot apply `+=' because `$var' is not defined "
		     . "in\nthe following conditions:\n  "
		     . join ("\n  ", map { $_->human } $undef_cond->conds)
		     . "\nEither define `$var' in these conditions,"
		     . " or use\n`+=' in the same conditions as"
		     . " the definitions.");
	    }
	  else
	    {
	      &define ($var, $owner, '+', $vcond, $value, $comment,
		       $where, $pretty);
	    }
	}
    }
  # 3. first assignment (=, :=, or +=)
  else
    {
      # There must be no previous value unless the user is redefining
      # an Automake variable or an AC_SUBST variable for an existing
      # condition.
      _check_ambiguous_condition ($self, $cond, $where)
	unless (!$new_var
		&& (($def->owner == VAR_AUTOMAKE && $owner != VAR_AUTOMAKE)
		    || $def->owner == VAR_CONFIGURE));

      # Never decrease an owner.
      $owner = $def->owner
	if ! $new_var && $owner < $def->owner;

      # Assignments to a macro set its location.  We don't adjust
      # locations for `+='.  Ideally I suppose we would associate
      # line numbers with random bits of text.
      $def = new Automake::VarDef ($var, $value, $comment, $where->clone,
				   $type, $owner, $pretty);
      $self->set ($cond, $def);
      push @_var_order, $var;
    }

  # Call any defined hook.  This helps to update some internal state
  # *while* parsing the file.  For instance the handling of SUFFIXES
  # requires this (see var_SUFFIXES_trigger).
  &{$_hooks{$var}}($type, $value) if exists $_hooks{$var};
}

=item C<variable_delete ($varname, [@conds])>

Forget about C<$varname> under the conditions C<@conds>, or completely
if C<@conds> is empty.

=cut

sub variable_delete ($@)
{
  my ($var, @conds) = @_;

  if (!@conds)
    {
      delete $_variable_dict{$var};
    }
  else
    {
      for my $cond (@conds)
	{
	  delete $_variable_dict{$var}{'defs'}{$cond};
	}
    }
}

=item C<$str = variables_dump>

Return a string describing all we know about all variables.
For debugging.

=cut

sub variables_dump ()
{
  my $text = "All variables:\n{\n";
  foreach my $var (sort { $a->name cmp $b->name } variables)
    {
      $text .= $var->dump;
    }
  $text .= "}\n";
  return $text;
}


=item C<$var = set_seen ($varname)>

=item C<$var = $var-E<gt>set_seen>

Mark all definitions of this variable as examined, if the variable
exists.  See L<Automake::VarDef::set_seen>.

Return the C<Variable> object if the variable exists, or 0
otherwise (i.e., as the C<var> function).

=cut

sub set_seen ($)
{
  my ($self) = @_;
  $self = ref $self ? $self : var $self;

  return 0 unless $self;

  for my $c ($self->conditions->conds)
    {
      $self->rdef ($c)->set_seen;
    }

  return $self;
}


=item C<$count = require_variables ($where, $reason, $cond, @variables)>

Make sure that each supplied variable is defined in C<$cond>.
Otherwise, issue a warning showing C<$reason> (C<$reason> should be
the reason why these variable are required, for instance C<'option foo
used'>).  If we know which macro can define this variable, hint the
user.  Return the number of undefined variables.

=cut

sub require_variables ($$$@)
{
  my ($where, $reason, $cond, @vars) = @_;
  my $res = 0;
  $reason .= ' but ' unless $reason eq '';

 VARIABLE:
  foreach my $var (@vars)
    {
      # Nothing to do if the variable exists.
      next VARIABLE
	if vardef ($var, $cond);

      my $text = "$reason`$var' is undefined\n";
      my $v = var $var;
      if ($v)
	{
	  my $undef_cond = $v->not_always_defined_in_cond ($cond);
	  next VARIABLE
	    if $undef_cond->false;
	  $text .= ("in the following conditions:\n  "
		    . join ("\n  ", map { $_->human } $undef_cond->conds));
	}

      ++$res;

      if (exists $_am_macro_for_var{$var})
	{
	  $text .= "\nThe usual way to define `$var' is to add "
	    . "`$_am_macro_for_var{$var}'\nto `$configure_ac' and "
	    . "run `aclocal' and `autoconf' again.";
	}
      elsif (exists $_ac_macro_for_var{$var})
	{
	  $text .= "\nThe usual way to define `$var' is to add "
	    . "`$_ac_macro_for_var{$var}'\nto `$configure_ac' and "
	    . "run `autoconf' again.";
	}

      error $where, $text, uniq_scope => US_GLOBAL;
    }
  return $res;
}

=item C<$count = $var->requires_variables ($reason, @variables)>

Same as C<require_variables>, but a method of Automake::Variable.
C<@variables> should be defined in the same conditions as C<$var> is
defined.

=cut

sub requires_variables ($$@)
{
  my ($var, $reason, @args) = @_;
  my $res = 0;
  for my $cond ($var->conditions->conds)
    {
      $res += require_variables ($var->rdef ($cond)->location, $reason,
				 $cond, @args);
    }
  return $res;
}


=item C<variable_value ($var)>

Get the C<TRUE> value of a variable, warn if the variable is
conditionally defined.  C<$var> can be either a variable name
or a C<Automake::Variable> instance (this allows to calls sucha
as C<$var-E<gt>variable_value>).

=cut

sub variable_value ($)
{
    my ($var) = @_;
    my $v = ref ($var) ? $var : var ($var);
    return () unless $v;
    $v->check_defined_unconditionally;
    return $v->rdef (TRUE)->value;
}

=item C<$str = output_variables>

Format definitions for all variables.

=cut

sub output_variables ()
{
  my $res = '';
  # We output variables it in the same order in which they were
  # defined (skipping duplicates).
  my @vars = uniq @_var_order;

  # Output all the Automake variables.  If the user changed one,
  # then it is now marked as VAR_CONFIGURE or VAR_MAKEFILE.
  foreach my $var (@vars)
    {
      my $v = rvar $var;
      foreach my $cond ($v->conditions->conds)
	{
	  $res .= $v->output ($cond)
	    if $v->rdef ($cond)->owner == VAR_AUTOMAKE;
	}
    }

  # Now dump the user variables that were defined.
  foreach my $var (@vars)
    {
      my $v = rvar $var;
      foreach my $cond ($v->conditions->conds)
	{
	  $res .= $v->output ($cond)
	    if $v->rdef ($cond)->owner != VAR_AUTOMAKE;
	}
    }
  return $res;
}

=item C<$var-E<gt>traverse_recursively (&fun_item, &fun_collect, [cond_filter =E<gt> $cond_filter], [inner_expand =E<gt> 1])>

Split the value of the Automake::Variable C<$var> on space, and
traverse its components recursively.

If C<$cond_filter> is an C<Automake::Condition>, process any
conditions which are true when C<$cond_filter> is true.  Otherwise,
process all conditions.

We distinguish two kinds of items in the content of C<$var>.
Terms that look like C<$(foo)> or C<${foo}> are subvariables
and cause recursion.  Other terms are assumed to be filenames.

Each time a filename is encountered, C<&fun_item> is called with the
following arguments:

  ($var,        -- the Automake::Variable we are currently
                   traversing
   $val,        -- the item (i.e., filename) to process
   $cond,       -- the Condition for the $var definition we are
                   examinating (ignoring the recursion context)
   $full_cond)  -- the full Condition, taking into account
                   conditions inherited from parent variables
                   during recursion

If C<inner_expand> is set, variable references occuring in filename
(as in C<$(BASE).ext>) are expansed before the filename is passed to
C<&fun_item>.

C<&fun_item> may return a list of items, they will be passed to
C<&fun_store> later on.  Define C<&fun_item> as C<undef> when it serve
no purpose, this will speed things up.

Once all items of a variable have been processed, the result (of the
calls to C<&fun_items>, or of recursive traversals of subvariables)
are passed to C<&fun_collect>.  C<&fun_collect> receives three
arguments:

  ($var,         -- the variable being traversed
   $parent_cond, -- the Condition inherited from parent
                    variables during recursion
   @condlist)    -- a list of [$cond, @results] pairs
                    where each $cond appear only once, and @result
                    are all the results for this condition.

Typically you should do C<$cond->merge ($parent_cond)> to recompute
the C<$full_cond> associated to C<@result>.  C<&fun_collect> may
return a list of items, that will be used as the result of
C<Automake::Variable::traverse_recursively> (the top-level, or its
recursive calls).

=cut

# Contains a stack of `from' and `to' parts of variable
# substitutions currently in force.
my @_substfroms;
my @_substtos;
sub traverse_recursively ($&&;%)
{
  ++$_traversal;
  @_substfroms = ();
  @_substtos = ();
  my ($var, $fun_item, $fun_collect, %options) = @_;
  my $cond_filter = $options{'cond_filter'};
  my $inner_expand = $options{'inner_expand'};
  return $var->_do_recursive_traversal ($var,
					$fun_item, $fun_collect,
					$cond_filter, TRUE, $inner_expand)
}

# The guts of Automake::Variable::traverse_recursively.
sub _do_recursive_traversal ($$&&$$$)
{
  my ($var, $parent, $fun_item, $fun_collect, $cond_filter, $parent_cond,
      $inner_expand) = @_;

  $var->set_seen;

  if ($var->{'scanned'} == $_traversal)
    {
      err_var $var, "variable `" . $var->name() . "' recursively defined";
      return ();
    }
  $var->{'scanned'} = $_traversal;

  my @allresults = ();
  my $cond_once = 0;
  foreach my $cond ($var->conditions->conds)
    {
      if (ref $cond_filter)
	{
	  # Ignore conditions that don't match $cond_filter.
	  next if ! $cond->true_when ($cond_filter);
	  # If we found out several definitions of $var
	  # match $cond_filter then we are in trouble.
	  # Tell the user we don't support this.
	  $var->check_defined_unconditionally ($parent, $parent_cond)
	    if $cond_once;
	  $cond_once = 1;
	}
      my @result = ();
      my $full_cond = $cond->merge ($parent_cond);

      my @to_process = $var->value_as_list ($cond, $parent, $parent_cond);
      while (@to_process)
	{
	  my $val = shift @to_process;
	  # If $val is a variable (i.e. ${foo} or $(bar), not a filename),
	  # handle the sub variable recursively.
	  # (Backslashes before `}' and `)' within brackets are here to
	  # please Emacs's indentation.)
	  if ($val =~ /^\$\{([^\}]*)\}$/ || $val =~ /^\$\(([^\)]*)\)$/)
	    {
	      my $subvarname = $1;

	      # If the user uses a losing variable name, just ignore it.
	      # This isn't ideal, but people have requested it.
	      next if ($subvarname =~ /\@.*\@/);

	      # See if the variable is actually a substitution reference
	      my ($from, $to);
              # This handles substitution references like ${foo:.a=.b}.
	      if ($subvarname =~ /^([^:]*):([^=]*)=(.*)$/o)
		{
		  $subvarname = $1;
		  $to = $3;
		  $from = quotemeta $2;
		}

	      my $subvar = var ($subvarname);
	      # Don't recurse into undefined variables.
	      next unless $subvar;

	      push @_substfroms, $from;
	      push @_substtos, $to;

	      my @res = $subvar->_do_recursive_traversal ($parent,
							  $fun_item,
							  $fun_collect,
							  $cond_filter,
							  $full_cond,
							  $inner_expand);
	      push (@result, @res);

	      pop @_substfroms;
	      pop @_substtos;

	      next;
	    }
	  # Try to expand variable references inside filenames such as
	  # `$(NAME).txt'.  We do not handle `:.foo=.bar'
	  # substitutions, but it would make little sense to use this
	  # here anyway.
	  elsif ($inner_expand
		 && ($val =~ /\$\{([^\}]*)\}/ || $val =~ /\$\(([^\)]*)\)/))
	    {
	      my $subvarname = $1;
	      my $subvar = var $subvarname;
	      if ($subvar)
		{
		  # Replace the reference by its value, and reschedule
		  # for expansion.
		  foreach my $c ($subvar->conditions->conds)
		    {
		      if (ref $cond_filter)
			{
			  # Ignore conditions that don't match $cond_filter.
			  next if ! $c->true_when ($cond_filter);
			  # If we found out several definitions of $var
			  # match $cond_filter then we are in trouble.
			  # Tell the user we don't support this.
			  $subvar->check_defined_unconditionally ($var,
								  $full_cond)
			    if $cond_once;
			  $cond_once = 1;
			}
		      my $subval = $subvar->rdef ($c)->value;
		      $val =~ s/\$\{$subvarname\}/$subval/g;
		      $val =~ s/\$\($subvarname\)/$subval/g;
		      unshift @to_process, split (' ', $val);
		    }
		  next;
		}
	      # We do not know any variable with this name.  Fall through
	      # to filename processing.
	    }

	  if ($fun_item) # $var is a filename we must process
	    {
	      my $substnum=$#_substfroms;
	      while ($substnum >= 0)
		{
		  $val =~ s/$_substfroms[$substnum]$/$_substtos[$substnum]/
		    if defined $_substfroms[$substnum];
		  $substnum -= 1;
		}

	      # Make sure you update the doc of
	      # Automake::Variable::traverse_recursively
	      # if you change the prototype of &fun_item.
	      my @transformed = &$fun_item ($var, $val, $cond, $full_cond);
	      push (@result, @transformed);
	    }
	}
      push (@allresults, [$cond, @result]) if @result;
    }

  # We only care about _recursive_ variable definitions.  The user
  # is free to use the same variable several times in the same definition.
  $var->{'scanned'} = -1;

  # Make sure you update the doc of Automake::Variable::traverse_recursively
  # if you change the prototype of &fun_collect.
  return &$fun_collect ($var, $parent_cond, @allresults);
}

# $VARNAME
# _gen_varname ($BASE, @DEFINITIONS)
# ---------------------------------
# Return a variable name starting with $BASE, that will be
# used to store definitions @DEFINITIONS.
# @DEFINITIONS is a list of pair [$COND, @OBJECTS].
#
# If we already have a $BASE-variable containing @DEFINITIONS, reuse it.
# This way, we avoid combinatorial explosion of the generated
# variables.  Especially, in a Makefile such as:
#
# | if FOO1
# | A1=1
# | endif
# |
# | if FOO2
# | A2=2
# | endif
# |
# | ...
# |
# | if FOON
# | AN=N
# | endif
# |
# | B=$(A1) $(A2) ... $(AN)
# |
# | c_SOURCES=$(B)
# | d_SOURCES=$(B)
#
# The generated c_OBJECTS and d_OBJECTS will share the same variable
# definitions.
#
# This setup can be the case of a testsuite containing lots (>100) of
# small C programs, all testing the same set of source files.
sub _gen_varname ($@)
{
  my $base = shift;
  my $key = '';
  foreach my $pair (@_)
    {
      my ($cond, @values) = @$pair;
      $key .= "($cond)@values";
    }

  return $_gen_varname{$base}{$key} if exists $_gen_varname{$base}{$key};

  my $num = 1 + keys (%{$_gen_varname{$base}});
  my $name = "${base}_${num}";
  $_gen_varname{$base}{$key} = $name;
  return $name;
}

=item C<$resvar = transform_variable_recursively ($var, $resvar, $base, $nodefine, $where, &fun_item, [%options])>

=item C<$resvar = $var-E<gt>transform_variable_recursively ($resvar, $base, $nodefine, $where, &fun_item, [%options])>

Traverse C<$var> recursively, and create a C<$resvar> variable in
which each filename in C<$var> have been transformed using
C<&fun_item>.  (C<$var> may be a variable name in the first syntax.
It must be an C<Automake::Variable> otherwise.)

Helper variables (corresponding to sub-variables of C<$var>) are
created as needed, using C<$base> as prefix.

Arguments are:
  $var       source variable to traverse
  $resvar    resulting variable to define
  $base      prefix to use when naming subvariables of $resvar
  $nodefine  if true, traverse $var but do not define any variable
             (this assumes &fun_item has some useful side-effect)
  $where     context into which variable definitions are done
  &fun_item  a transformation function -- see the documentation
             of &fun_item in Automake::Variable::traverse_recursively.

This returns the string C<"\$($RESVAR)">.

C<%options> is a list of options to pass to
C<Variable::traverse_recursively> (see this method).

=cut

sub transform_variable_recursively ($$$$$&;%)
{
  my ($var, $resvar, $base, $nodefine, $where, $fun_item, %options) = @_;

  $var = ref $var ? $var : rvar $var;

  my $res = $var->traverse_recursively
    ($fun_item,
     # The code that define the variable holding the result
     # of the recursive transformation of a subvariable.
     sub {
       my ($subvar, $parent_cond, @allresults) = @_;
       # Find a name for the variable, unless this is the top-variable
       # for which we want to use $resvar.
       my $varname =
	 ($var != $subvar) ? _gen_varname ($base, @allresults) : $resvar;
       # Define the variable if required.
       unless ($nodefine)
	 {
	   # If the new variable is the source variable, we assume
	   # we are trying to override a user variable.  Delete
	   # the old variable first.
	   variable_delete ($varname) if $varname eq $var->name;
	   # Define an empty variable in condition TRUE if there is no
	   # result.
	   @allresults = ([TRUE, '']) unless @allresults;
	   # Define the rewritten variable in all conditions not
	   # already covered by user definitions.
	   foreach my $pair (@allresults)
	     {
	       my ($cond, @result) = @$pair;
	       my $var = var $varname;
	       my @conds = ($var
			    ? $var->not_always_defined_in_cond ($cond)->conds
			    : $cond);

	       foreach (@conds)
		 {
		   define ($varname, VAR_AUTOMAKE, '', $_, "@result",
			   '', $where, VAR_PRETTY);
		 }
	     }
	   set_seen $varname;
	 }
       return "\$($varname)";
     },
     %options);
  return $res;
}


=back

=head1 SEE ALSO

L<Automake::VarDef>, L<Automake::Condition>,
L<Automake::DisjConditions>, L<Automake::Location>.

=cut

1;

### Setup "GNU" style for perl-mode and cperl-mode.
## Local Variables:
## perl-indent-level: 2
## perl-continued-statement-offset: 2
## perl-continued-brace-offset: 0
## perl-brace-offset: 0
## perl-brace-imaginary-offset: 0
## perl-label-offset: -2
## cperl-indent-level: 2
## cperl-brace-offset: 0
## cperl-continued-brace-offset: 0
## cperl-label-offset: -2
## cperl-extra-newline-before-brace: t
## cperl-merge-trailing-else: nil
## cperl-continued-statement-offset: 2
## End:
