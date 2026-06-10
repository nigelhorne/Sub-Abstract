package Sub::Abstract;

# Minimum required Perl version: 5.8 (Attribute::Handlers became core in 5.8).
use 5.008;
use strict;
use warnings;
use autodie qw(:all);

use Attribute::Handlers;
use Carp              qw(croak carp);   # carp reserved for future non-fatal paths
use Readonly;
use Params::Validate::Strict 0.33 qw(validate_strict);
use Return::Set       qw(set_return);

# NOTE: Params::Get is available for any future method that accepts named
# parameters.  import() uses a positional calling convention imposed by
# Perl's "use" mechanism and therefore cannot use named params.

=head1 NAME

Sub::Abstract - Abstract (virtual) methods for plain-Perl OO

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Self-referential constant: the canonical name of this package.
Readonly::Scalar my $SELF => __PACKAGE__;

# Validation schema for a single Perl sub name passed to import().
# Matches any legal Perl identifier: starts with _ or letter, then \w*.
Readonly::Scalar my $SUB_NAME_SCHEMA => {
	name => {
		type  => 'string',
		regex => qr/\A[_a-zA-Z]\w*\z/,
	}
};

# ---------------------------------------------------------------------------
# Public variables
# ---------------------------------------------------------------------------

# Set to a true value to suppress all abstract-method croaks globally.
# Always use 'local' in tests to prevent state from bleeding between cases.
our $BYPASS = 0;

# Runtime tunables.  Modify $config{harness_bypass} to control whether
# HARNESS_ACTIVE suppresses enforcement.  May be extended in future releases.
our %config = (
	harness_bypass => 1,    # 1 = suppress croaks when HARNESS_ACTIVE is set
);

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

# Pending (owner_pkg, sub_name) pairs queued by import() during compilation.
# Populated before CHECK fires; consumed and cleared by the CHECK block.
my @_pending;

# Becomes 1 once the CHECK block has fired.
# import() consults this to decide whether to queue or wrap immediately.
my $_post_check = 0;

# ---------------------------------------------------------------------------
# ATTRIBUTE HANDLER
# ---------------------------------------------------------------------------

# UNIVERSAL::Abstract :ATTR(CODE,CHECK)
# Purpose      : Replace any sub decorated with :Abstract with the croak
#                closure returned by _wrap().  Fires once per decorated sub
#                at CHECK time, after all subs in all packages are compiled.
# Entry        : Invoked by Attribute::Handlers with six positional args:
#                  $package  -- the package in which the sub was declared
#                  $symbol   -- the typeglob for the sub
#                  $referent -- the CODE ref (stub body; discarded)
#                  $attr     -- the attribute name ('Abstract')
#                  $data     -- attribute arguments (undef for :Abstract)
#                  $phase    -- 'CHECK'
# Exit status  : Returns nothing (void); replaces *{$symbol} in the stash.
# Side effects : Overwrites the CODE slot for $symbol in $package's stash.
# Notes        : Compiled inside Sub::Abstract so that caller(1) inside
#                _assert_private_caller resolves to Sub::Abstract rather
#                than the calling package -- allowing the guard to pass.
#                Installing :Abstract in UNIVERSAL gives all packages access
#                after a single "use Sub::Abstract", at the cost of global
#                namespace pollution (see KNOWN LIMITATIONS).
#                $referent, $attr, $data, $phase are received but unused;
#                they are named for documentation clarity only.
sub UNIVERSAL::Abstract :ATTR(CODE,CHECK) {
	my ($package, $symbol, undef, undef, undef, undef) = @_;

	# Extract the bare sub name from the typeglob, then replace the glob.
	my $sub_name = *{$symbol}{NAME};
	no warnings 'redefine';
	*{$symbol} = _wrap($package, $sub_name);
	return;
}

# ---------------------------------------------------------------------------
# PUBLIC INTERFACE
# ---------------------------------------------------------------------------

=head1 SYNOPSIS

    package Animal;
    use Sub::Abstract;

    # Attribute form (stub body required for Attribute::Handlers)
    sub speak :Abstract { }
    sub eat   :Abstract { }

    # Declarative form (no stub body needed)
    use Sub::Abstract qw(speak eat);

    package Dog;
    our @ISA = ('Animal');
    sub speak { 'Woof' }    # satisfies the contract; wrapper never fires
    # forgot eat -- runtime croak when called

=head1 DESCRIPTION

Enforces abstract (virtual) method contracts for plain-Perl OO without
requiring Moose or Moo.  A subroutine decorated with C<:Abstract> (or
named in C<use Sub::Abstract qw(...)>) is replaced at C<CHECK> time with
a wrapper that C<Carp::croak>s whenever it is reached.

Perl's MRO ensures the wrapper is only reached when no subclass in the
call chain has provided an implementation: if C<Dog::speak> exists, the
wrapper installed in C<Animal::speak> is never called.

This module is only meaningful for plain-Perl OO or packages that do not
use a full object framework.  Moo and Moose handle abstract/required
methods in their own object systems.

=head2 Two usage forms

=over 4

=item Attribute form (preferred)

    sub speak :Abstract { }

The C<:Abstract> attribute is registered in C<UNIVERSAL> via
L<Attribute::Handlers> when C<Sub::Abstract> is loaded, so every package
has access to it without further C<use> or inheritance.  A stub body
(even an empty one) is required because C<Attribute::Handlers> needs a
C<CODE> ref.  The stub is replaced at C<CHECK> time.

=item Declarative form

    use Sub::Abstract qw(speak eat);

Each named method is installed as an abstract-croak wrapper at C<CHECK>
time (or immediately if the module is loaded past C<CHECK>).  No stub body
is needed.

=back

=head2 Bypass for testing

Either condition alone (OR logic) suppresses the croak at call time:

=over 4

=item * C<$Sub::Abstract::BYPASS> set to a true value.  Use C<local> in tests.
Checked first; short-circuits the second condition.

=item * C<$ENV{HARNESS_ACTIVE}> set (the convention used by L<Test::Harness>/prove)
B<and> C<$config{harness_bypass}> is truthy (the default).

=back

The C<HARNESS_ACTIVE> bypass can be disabled:

    $Sub::Abstract::config{harness_bypass} = 0;

B<Important:> setting C<$BYPASS> to any truthy value takes full precedence.
Even with C<harness_bypass = 0>, a truthy C<$BYPASS> still suppresses the
croak.  The two guards use C<||> (short-circuit OR) and C<$BYPASS> is
checked first.  See L</Bypass precedence> under KNOWN LIMITATIONS.

=head2 Error message format

    speak() is an abstract method of Animal and must be implemented by Dog

=head1 PUBLIC INTERFACE

=head2 import

    use Sub::Abstract;                   # attribute form -- no arguments
    use Sub::Abstract qw(speak eat);    # declarative form

=head3 Purpose

With B<no arguments>: loads the module and makes the C<:Abstract> attribute
globally available via C<UNIVERSAL>.  No stash entries are modified.

With B<one or more method names>: installs abstract-croak wrappers for
those methods in the calling package.  Wrappers are installed at C<CHECK>
time when called during compilation, or immediately when called after
C<CHECK> has fired.  Validation is fail-fast and all-or-nothing: if any
name is invalid the entire call croaks before touching the stash.

=head3 Arguments

=over 4

=item C<$class> (required, implicit via C<use>)

The invocant.  Always C<'Sub::Abstract'> in normal usage; not validated
because Perl's C<use> mechanism enforces it.

=item C<@methods> (optional)

Zero or more Perl sub names, each matching C</\A[_a-zA-Z]\w*\z/>.
An undef or reference in this list is coerced to the empty string before
validation, producing a clear identifier-mismatch error.

=back

=head3 Returns

The class name (C<'Sub::Abstract'>) as a plain string.  All call paths
return this value, consistent with the sister modules C<Sub::Private>
and C<Sub::Protected>.

=head3 Example

    package MyBase;
    use Sub::Abstract qw(render serialize);

    package MyConcrete;
    our @ISA = ('MyBase');
    sub render    { ... }    # satisfies render contract
    sub serialize { ... }    # satisfies serialize contract

    # MyBase->new->render croaks; MyConcrete->new->render does not.

=head3 API SPECIFICATION

=head4 Input

    # import() uses positional arguments imposed by Perl's "use" mechanism;
    # named parameters are not applicable here.
    # Each element of @methods is validated individually against:
    {
        name => {
            type  => 'string',
            regex => qr/\A[_a-zA-Z]\w*\z/,
        }
    }

=head4 Output

    { type => 'string' }    # always returns the class name ('Sub::Abstract')

=head3 PSEUDOCODE

    import($class, @methods):
        IF @methods is empty
            RETURN class name      # attribute form; nothing to install
        FOR EACH name in @methods
            coerce undef/ref to empty string
            validate against /\A[_a-zA-Z]\w*\z/ via validate_strict()
            CROAK if invalid       # fail-fast; no stash modification
        END FOR
        owner_pkg <- caller package
        IF post_check flag is set  # CHECK has already fired
            FOR EACH name: _process_one(owner_pkg, name)
        ELSE                       # still compiling; queue for CHECK
            FOR EACH name: push [owner_pkg, name] onto @_pending
        END IF
        RETURN class name

=head3 MESSAGES

    Message                                              Meaning / Action
    -------                                              ----------------
    Sub::Abstract->import: 'NAME' is not a valid         NAME failed the identifier regex
    Perl identifier                                      /\A[_a-zA-Z]\w*\z/.  Common causes:
                                                         leading digit, hyphen, non-ASCII
                                                         character, undef passed where a name
                                                         was expected, or a reference in the
                                                         list.  Action: inspect the argument
                                                         list passed to "use Sub::Abstract
                                                         qw(...)".

=cut

sub import {
	my ($class, @subs) = @_;

	# Only do stash work when sub names were actually supplied.
	# With no arguments the :Abstract attribute is already globally available.
	if (@subs) {
		# Validate every name before touching the stash.
		# Fail fast, all-or-nothing: no partial wrapping on bad input.
		for my $sub_name (@subs) {
			# Coerce undef and references to empty string so the validator
			# produces a meaningful "'' is not a valid identifier" message.
			my $check = (defined $sub_name && !ref $sub_name) ? $sub_name : q{};

			# BUG FIX: use the "eval { ...; 1 } or do { $err = $@ }" pattern
			# rather than "eval { ... }; croak if $@".  A DESTROY method fired
			# between the eval and the $@ test can overwrite $@, causing the
			# error to be silently swallowed or a wrong message to be reported.
			my $ok = eval {
				validate_strict(
					schema => $SUB_NAME_SCHEMA,
					input  => { name => $check },
				);
				1;
			};
			croak "$SELF->import: '$check' is not a valid Perl identifier"
				unless $ok;
		}

		# Decide whether to wrap immediately or queue for CHECK.
		my $owner_pkg = caller;
		if ($_post_check) {
			# CHECK has already fired: install wrappers directly into the stash.
			for my $sub_name (@subs) {
				_process_one($owner_pkg, $sub_name);
			}
		}
		else {
			# Still in compilation: queue each pair for CHECK to drain.
			for my $sub_name (@subs) {
				push @_pending, [ $owner_pkg, $sub_name ];
			}
		}
	}

	# Single return path: consistent with Sub::Private and Sub::Protected.
	return set_return($class, { type => 'string' });
}

# ---------------------------------------------------------------------------
# CHECK-TIME PROCESSING
# ---------------------------------------------------------------------------

# CHECK block.
# Purpose      : Drain @_pending (all import() calls queued during compilation)
#                and mark the module post-CHECK so future import() calls wrap
#                immediately rather than queuing.
# Ordering note: $_post_check is set to 1 BEFORE @_pending is drained.
#                This means if _process_one were ever to trigger import()
#                (it does not in practice), that nested import() would call
#                _process_one directly rather than re-queuing.
#                The _assert_private_caller guard inside _process_one is
#                satisfied because this CHECK block is compiled inside
#                Sub::Abstract: caller(1) resolves to Sub::Abstract.
CHECK {
	$_post_check = 1;
	_process_one(@{$_}) for @_pending;
	@_pending = ();
}

# ---------------------------------------------------------------------------
# PRIVATE SUBROUTINES
# ---------------------------------------------------------------------------

# _process_one
# Purpose      : Install an abstract-croak wrapper for one named method in
#                a given package.
# Entry        : $owner_pkg -- the package declaring the abstract method
#                $sub_name  -- unqualified method name (a valid identifier)
# Exit status  : Returns nothing (void); the package stash is modified.
# Side effects : Overwrites *{"${owner_pkg}::${sub_name}"} with the closure
#                returned by _wrap().  Creates the glob entry if it does not
#                yet exist (the declarative form requires no pre-existing stub).
# Notes        : Unlike Sub::Private::_process_one there is no pre-existence
#                check: abstract methods in the declarative form have no body.
#                Protected by _assert_private_caller (via the bypass guard)
#                so that external callers cannot invoke this directly.
sub _process_one {
	my ($owner_pkg, $sub_name) = @_;

	# Guard: only Sub::Abstract itself may call this.
	# Bypass is active under the test harness or when $BYPASS is set.
	_assert_private_caller('_process_one')
		unless $BYPASS || ($config{harness_bypass} && $ENV{HARNESS_ACTIVE});

	# Install the wrapper; suppress redefine warnings for the attribute form.
	no strict 'refs';
	no warnings 'redefine';
	*{"${owner_pkg}::${sub_name}"} = _wrap($owner_pkg, $sub_name);
	return;
}

# _wrap
# Purpose      : Build and return the abstract-enforcement closure for one
#                method.  The closure croaks with a message naming both the
#                abstract owner package and the concrete invocant class.
# Entry        : $owner_pkg -- the package declaring the abstract method
#                $sub_name  -- unqualified method name (for error messages)
# Exit status  : Returns a new CODE ref (the enforcement wrapper).
# Side effects : None.  The closure captures $owner_pkg and $sub_name by
#                value; $BYPASS and %config are read at call time (not
#                capture time), so runtime changes to them take effect.
# Notes        : No $code argument and no delegation (unlike Sub::Private).
#                Calling an abstract method is always an error; there is
#                nothing to delegate to.
#                Invocant extraction: (ref($_[0]) || $_[0]) // '<undef>'
#                  ref()   -- for blessed objects: returns the concrete class
#                  $_[0]   -- for class-method calls: the package name string
#                  '<undef>' -- guard against a completely absent invocant
#                $BYPASS is consulted first (short-circuit ||); setting
#                harness_bypass=0 does NOT re-enable enforcement while
#                $BYPASS is truthy (see KNOWN LIMITATIONS).
sub _wrap {
	my ($owner_pkg, $sub_name) = @_;

	# Guard: same bypass semantics as _process_one.
	_assert_private_caller('_wrap')
		unless $BYPASS || ($config{harness_bypass} && $ENV{HARNESS_ACTIVE});

	# Return a closure that enforces the abstract contract at call time.
	return sub {
		return if $BYPASS;
		return if $config{harness_bypass} && $ENV{HARNESS_ACTIVE};
		my $invocant = ref($_[0]) || $_[0] // '<undef>';
		croak "${sub_name}() is an abstract method of ${owner_pkg}"
			. " and must be implemented by ${invocant}";
	};
}

# _assert_private_caller
# Purpose      : Croak if the guarded private method (_wrap or _process_one)
#                was invoked from outside Sub::Abstract.
# Entry        : $method_name -- the name of the guarded method (used only
#                in the error message; not validated).
# Exit status  : Returns normally when the immediate caller of the guarded
#                function is Sub::Abstract.  Croaks otherwise.
# Side effects : May croak.
# Notes        : Uses caller(1), not caller(0).
#                Inside _assert_private_caller:
#                  caller(0) = Sub::Abstract (this sub's own frame)
#                  caller(1) = the package that called _wrap/_process_one
#                For calls from CHECK{} or UNIVERSAL::Abstract (both compiled
#                inside Sub::Abstract), caller(1) = Sub::Abstract -- allowed.
#                For direct external calls to _wrap or _process_one, caller(1)
#                is the calling package -- denied unless bypass is active.
#                The '//' fallback to q{} handles the pathological case where
#                caller(1) returns undef (top-level call outside any sub);
#                this path is practically unreachable in production.
#                This guard is a lint tool, not a security fence: code that
#                injects a sub into the Sub::Abstract namespace can defeat it
#                (see KNOWN LIMITATIONS).
sub _assert_private_caller {
	my $method_name = $_[0];
	my $caller = (caller(1))[0] // q{};

	# Single conditional croak; one return at the bottom.
	croak "${method_name}() is a private method of $SELF"
		. " and cannot be called from ${caller}"
		unless $caller eq $SELF;
	return;
}

1;

__END__

=head1 KNOWN LIMITATIONS

=over 4

=item Runtime-only enforcement

Checks are runtime only.  There is no compile-time scan of C<@ISA> trees
to verify that all abstract methods are implemented -- that would require
knowing all subclasses at compile time, which is not possible in general
Perl.  A future C<use Sub::Abstract -verify> pragma (walking C<@ISA> at
C<INIT> time) is under consideration.

=item C<can()> returns the croak-stub

Because the stash entry is replaced with a wrapper closure,
C<< Animal->can('speak') >> returns the wrapper (a truthy CODE ref) rather
than C<undef>.  Code that duck-types on C<can()> will silently believe the
abstract method is implemented and then crash when it is called.  A future
release may add a caller-aware C<can()> override.

=item UNIVERSAL namespace pollution

The C<:Abstract> attribute is installed in C<UNIVERSAL>, which means
C<UNIVERSAL::Abstract> is added to the global namespace for the lifetime of
the process.  Any code loaded after C<Sub::Abstract> can use C<:Abstract>
without a C<use Sub::Abstract> statement, which can be surprising in large
codebases.

=item Bypass precedence

The enforcement guard is C<$BYPASS || ($config{harness_bypass} &&
$ENV{HARNESS_ACTIVE})>.  Because C<$BYPASS> is checked first with
short-circuit C<||>, setting C<$config{harness_bypass} = 0> does B<not>
re-enable enforcement when C<$BYPASS> is truthy.  To test enforcement
inside a harness you must set both:

    local $Sub::Abstract::BYPASS = 0;
    local $Sub::Abstract::config{harness_bypass} = 0;

=item Thread safety

C<@_pending> and C<$_post_check> are package-global lexicals.  Concurrent
threads loading modules that call C<import()> before C<CHECK> fires may
race on these variables.  This module is not safe for concurrent use
across threads during the compilation phase.

=item DESTROY and Perl 5.42+

On Perl 5.42 and later, exceptions thrown inside C<DESTROY> are not
propagated to the caller -- Perl emits a C<(in cleanup)> message to STDERR
instead.  If a class marks C<DESTROY> as abstract, the enforcement croak
will be silently discarded rather than propagating.  Test with C<lives_ok>,
not C<throws_ok>, for C<DESTROY> paths on modern Perl.

=item _assert_private_caller is a lint tool, not a security fence

Injecting a subroutine directly into the C<Sub::Abstract> namespace (via
glob assignment C<*Sub::Abstract::injected = sub { ... }>) defeats the
C<caller(1)> check because the injected sub runs inside the C<Sub::Abstract>
package.  The guard deters accidental misuse; it does not prevent deliberate
circumvention.

=item Not for Moo/Moose

Moo and Moose handle required/abstract methods in their own object systems.
This module is for plain-Perl OO only.

=back

=head1 BUGS

=over 4

=item eval/$@ clobber race (fixed in current release)

The original validation loop used:

    eval { validate_strict(...) };
    croak "..." if $@;

A C<DESTROY> method invoked between the C<eval> and the C<if ($@)> test
could overwrite C<$@>, causing the validation error to be silently dropped
or replaced with an unrelated message.

B<Fix:> the current code uses:

    my $ok = eval { validate_strict(...); 1 };
    croak "..." unless $ok;

The success flag C<$ok> is set inside the C<eval> itself and is unaffected
by any C<DESTROY> calls that occur after the C<eval> exits.

=item Implicit $_ in postfix for (fixed in current release)

The original dispatch branches used implicit C<$_> as the iterator:

    _process_one($owner_pkg, $_) for @subs;
    push @_pending, [ $owner_pkg, $_ ] for @subs;

While postfix C<for> does localize C<$_>, the implicit iterator makes it
harder to audit whether the caller's C<$_> is preserved and obscures the
intent.

B<Fix:> both loops now use explicit named variables:

    for my $sub_name (@subs) { _process_one($owner_pkg, $sub_name) }
    for my $sub_name (@subs) { push @_pending, [ $owner_pkg, $sub_name ] }

=item Duplicate set_return call (fixed in current release)

The original C<import()> called C<set_return($class, ...)> on two separate
return paths (an early return for the no-args case and the normal return).
This is a minor inefficiency and a maintenance hazard: any future change to
the return schema must be applied in two places.

B<Fix:> C<import()> now has a single C<return set_return(...)> statement at
the end; the no-args case falls through to it via a conditional block.

=back

=head1 FORMAL SPECIFICATION

The following schemas formally specify the C<AbstractCroak> operation
and the compile-time registration state.

    -- Type abbreviations
    Package  == seq CHAR     -- a non-empty Perl package name string
    SubName  == seq CHAR     -- a Perl identifier string

    -- System state (runtime)
    +-Registry--------------------------------------------+
    | abstract  : P (Package x SubName)                   |
    | bypass    : BOOL                                    |
    | config    : { harness_bypass : BOOL }               |
    +-----------------------------------------------------+

    -- Initial state
    +-InitRegistry----------------------------------------+
    | Registry                                            |
    |-----------------------------------------------------|
    | abstract  = {}                                      |
    | bypass    = false                                   |
    | config    = { harness_bypass |-> true }             |
    +-----------------------------------------------------+

    -- Bypass predicate (OR logic; $BYPASS checked first)
    bypass_active(R) <=>
        R.bypass
        or (R.config.harness_bypass and HARNESS_ACTIVE)

    -- AbstractCroak: fires when the wrapper is reached
    -- (Perl MRO guarantees no subclass override exists)
    +-AbstractCroak---------------------------------------+
    | Xi-Registry                                         |
    | invocant? : Package                                 |
    | owner?    : Package                                 |
    | name?     : SubName                                 |
    |-----------------------------------------------------|
    | (owner?, name?) in abstract                         |
    | not bypass_active =>                                |
    |   croak("name?()" ++ " is an abstract method of "  |
    |          ++ owner? ++ " and must be implemented by" |
    |          ++ invocant?)                              |
    +-----------------------------------------------------+

    -- Key difference from Sub::Private / Sub::Protected:
    --   No caller check is performed inside the wrapper.
    --   Reaching the wrapper already proves no subclass
    --   provided an implementation (MRO guarantees this).

=head1 DEPENDENCIES

L<Carp> (core),
L<Attribute::Handlers> (core since 5.8),
L<Readonly>,
L<Params::Validate::Strict>,
L<Return::Set>.

=head1 SEE ALSO

=over 4

=item * L<Test Dashboard|https://nigelhorne.github.io/Sub-Abstract/coverage/>

=item * L<Sub::Private>

Sister module enforcing strictly private (owner-only) access.

=item * L<Sub::Protected>

Sister module enforcing protected (owner + subclass) access.

=back

=head1 PUBLIC VARIABLES

=head2 C<$BYPASS>

Set to a true value to disable the abstract-method croak for all wrapped
subs.  Use C<local> in tests:

    local $Sub::Abstract::BYPASS = 1;

B<Warning:> any truthy value (including strings like C<"false">, C<"off">,
C<"no">) enables bypass, because Perl's truthiness is not English.

=head2 C<%config>

=over 4

=item C<harness_bypass> (default: 1)

When true, the abstract-method croak is suppressed whenever
C<$ENV{HARNESS_ACTIVE}> is set (the convention used by L<Test::Harness>/prove).
Set to 0 to test enforcement from within a test harness.

Note that C<$BYPASS> takes precedence: see L</Bypass precedence> under
KNOWN LIMITATIONS.

=back

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=head1 LICENCE AND COPYRIGHT

Copyright 2026 Nigel Horne.

Usage is subject to the GPL2 licence terms.
If you use it, please let me know.

=cut
