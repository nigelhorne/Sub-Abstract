# NAME

Sub::Abstract - Abstract (virtual) methods for plain-Perl OO

# VERSION

Version 0.01

# SYNOPSIS

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

# DESCRIPTION

Enforces abstract (virtual) method contracts for plain-Perl OO without
requiring Moose or Moo.  A subroutine decorated with `:Abstract` (or
named in `use Sub::Abstract qw(...)`) is replaced at `CHECK` time with
a wrapper that `Carp::croak`s whenever it is reached.

Perl's MRO ensures the wrapper is only reached when no subclass in the
call chain has provided an implementation: if `Dog::speak` exists, the
wrapper installed in `Animal::speak` is never called.

This module is only meaningful for plain-Perl OO or packages that do not
use a full object framework.  Moo and Moose handle abstract/required
methods in their own object systems.

## Two usage forms

- Attribute form (preferred)

        sub speak :Abstract { }

    The `:Abstract` attribute is registered in `UNIVERSAL` via
    [Attribute::Handlers](https://metacpan.org/pod/Attribute%3A%3AHandlers) when `Sub::Abstract` is loaded, so every package
    has access to it without further `use` or inheritance.  A stub body
    (even an empty one) is required because `Attribute::Handlers` needs a
    `CODE` ref.  The stub is replaced at `CHECK` time.

- Declarative form

        use Sub::Abstract qw(speak eat);

    Each named method is installed as an abstract-croak wrapper at `CHECK`
    time (or immediately if the module is loaded past `CHECK`).  No stub body
    is needed.

## Bypass for testing

Either condition alone (OR logic) suppresses the croak at call time:

- `$Sub::Abstract::BYPASS` set to a true value.  Use `local` in tests.
Checked first; short-circuits the second condition.
- `$ENV{HARNESS_ACTIVE}` set (the convention used by [Test::Harness](https://metacpan.org/pod/Test%3A%3AHarness)/prove)
**and** `$config{harness_bypass}` is truthy (the default).

The `HARNESS_ACTIVE` bypass can be disabled:

    $Sub::Abstract::config{harness_bypass} = 0;

**Important:** setting `$BYPASS` to any truthy value takes full precedence.
Even with `harness_bypass = 0`, a truthy `$BYPASS` still suppresses the
croak.  The two guards use `||` (short-circuit OR) and `$BYPASS` is
checked first.  See ["Bypass precedence"](#bypass-precedence) under KNOWN LIMITATIONS.

## Error message format

    speak() is an abstract method of Animal and must be implemented by Dog

# PUBLIC INTERFACE

## import

    use Sub::Abstract;                   # attribute form -- no arguments
    use Sub::Abstract qw(speak eat);    # declarative form

### Purpose

With **no arguments**: loads the module and makes the `:Abstract` attribute
globally available via `UNIVERSAL`.  No stash entries are modified.

With **one or more method names**: installs abstract-croak wrappers for
those methods in the calling package.  Wrappers are installed at `CHECK`
time when called during compilation, or immediately when called after
`CHECK` has fired.  Validation is fail-fast and all-or-nothing: if any
name is invalid the entire call croaks before touching the stash.

### Arguments

- `$class` (required, implicit via `use`)

    The invocant.  Always `'Sub::Abstract'` in normal usage; not validated
    because Perl's `use` mechanism enforces it.

- `@methods` (optional)

    Zero or more Perl sub names, each matching `/\A[_a-zA-Z]\w*\z/`.
    An undef or reference in this list is coerced to the empty string before
    validation, producing a clear identifier-mismatch error.

### Returns

The class name (`'Sub::Abstract'`) as a plain string.  All call paths
return this value, consistent with the sister modules `Sub::Private`
and `Sub::Protected`.

### Example

    package MyBase;
    use Sub::Abstract qw(render serialize);

    package MyConcrete;
    our @ISA = ('MyBase');
    sub render    { ... }    # satisfies render contract
    sub serialize { ... }    # satisfies serialize contract

    # MyBase->new->render croaks; MyConcrete->new->render does not.

### API SPECIFICATION

#### Input

    # import() uses positional arguments imposed by Perl's "use" mechanism;
    # named parameters are not applicable here.
    # Each element of @methods is validated individually against:
    {
        name => {
            type  => 'string',
            regex => qr/\A[_a-zA-Z]\w*\z/,
        }
    }

#### Output

    { type => 'string' }    # always returns the class name ('Sub::Abstract')

### PSEUDOCODE

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

### MESSAGES

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

# KNOWN LIMITATIONS

- Runtime-only enforcement

    Checks are runtime only.  There is no compile-time scan of `@ISA` trees
    to verify that all abstract methods are implemented -- that would require
    knowing all subclasses at compile time, which is not possible in general
    Perl.  A future `use Sub::Abstract -verify` pragma (walking `@ISA` at
    `INIT` time) is under consideration.

- `can()` returns the croak-stub

    Because the stash entry is replaced with a wrapper closure,
    `Animal->can('speak')` returns the wrapper (a truthy CODE ref) rather
    than `undef`.  Code that duck-types on `can()` will silently believe the
    abstract method is implemented and then crash when it is called.  A future
    release may add a caller-aware `can()` override.

- UNIVERSAL namespace pollution

    The `:Abstract` attribute is installed in `UNIVERSAL`, which means
    `UNIVERSAL::Abstract` is added to the global namespace for the lifetime of
    the process.  Any code loaded after `Sub::Abstract` can use `:Abstract`
    without a `use Sub::Abstract` statement, which can be surprising in large
    codebases.

- Bypass precedence

    The enforcement guard is `$BYPASS || ($config{harness_bypass} &&
    $ENV{HARNESS_ACTIVE})`.  Because `$BYPASS` is checked first with
    short-circuit `||`, setting `$config{harness_bypass} = 0` does **not**
    re-enable enforcement when `$BYPASS` is truthy.  To test enforcement
    inside a harness you must set both:

        local $Sub::Abstract::BYPASS = 0;
        local $Sub::Abstract::config{harness_bypass} = 0;

- Thread safety

    `@_pending` and `$_post_check` are package-global lexicals.  Concurrent
    threads loading modules that call `import()` before `CHECK` fires may
    race on these variables.  This module is not safe for concurrent use
    across threads during the compilation phase.

- DESTROY and Perl 5.42+

    On Perl 5.42 and later, exceptions thrown inside `DESTROY` are not
    propagated to the caller -- Perl emits a `(in cleanup)` message to STDERR
    instead.  If a class marks `DESTROY` as abstract, the enforcement croak
    will be silently discarded rather than propagating.  Test with `lives_ok`,
    not `throws_ok`, for `DESTROY` paths on modern Perl.

- \_assert\_private\_caller is a lint tool, not a security fence

    Injecting a subroutine directly into the `Sub::Abstract` namespace (via
    glob assignment `*Sub::Abstract::injected = sub { ... }`) defeats the
    `caller(1)` check because the injected sub runs inside the `Sub::Abstract`
    package.  The guard deters accidental misuse; it does not prevent deliberate
    circumvention.

- Not for Moo/Moose

    Moo and Moose handle required/abstract methods in their own object systems.
    This module is for plain-Perl OO only.

# BUGS

- eval/$@ clobber race (fixed in current release)

    The original validation loop used:

        eval { validate_strict(...) };
        croak "..." if $@;

    A `DESTROY` method invoked between the `eval` and the `if ($@)` test
    could overwrite `$@`, causing the validation error to be silently dropped
    or replaced with an unrelated message.

    **Fix:** the current code uses:

        my $ok = eval { validate_strict(...); 1 };
        croak "..." unless $ok;

    The success flag `$ok` is set inside the `eval` itself and is unaffected
    by any `DESTROY` calls that occur after the `eval` exits.

- Implicit $\_ in postfix for (fixed in current release)

    The original dispatch branches used implicit `$_` as the iterator:

        _process_one($owner_pkg, $_) for @subs;
        push @_pending, [ $owner_pkg, $_ ] for @subs;

    While postfix `for` does localize `$_`, the implicit iterator makes it
    harder to audit whether the caller's `$_` is preserved and obscures the
    intent.

    **Fix:** both loops now use explicit named variables:

        for my $sub_name (@subs) { _process_one($owner_pkg, $sub_name) }
        for my $sub_name (@subs) { push @_pending, [ $owner_pkg, $sub_name ] }

- Duplicate set\_return call (fixed in current release)

    The original `import()` called `set_return($class, ...)` on two separate
    return paths (an early return for the no-args case and the normal return).
    This is a minor inefficiency and a maintenance hazard: any future change to
    the return schema must be applied in two places.

    **Fix:** `import()` now has a single `return set_return(...)` statement at
    the end; the no-args case falls through to it via a conditional block.

# FORMAL SPECIFICATION

The following schemas formally specify the `AbstractCroak` operation
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

# DEPENDENCIES

[Carp](https://metacpan.org/pod/Carp) (core),
[Attribute::Handlers](https://metacpan.org/pod/Attribute%3A%3AHandlers) (core since 5.8),
[Readonly](https://metacpan.org/pod/Readonly),
[Params::Validate::Strict](https://metacpan.org/pod/Params%3A%3AValidate%3A%3AStrict),
[Return::Set](https://metacpan.org/pod/Return%3A%3ASet).

# SEE ALSO

- [Test Dashboard](https://nigelhorne.github.io/Sub-Abstract/coverage/)
- [Class::Abstract](https://metacpan.org/pod/Class%3A%3AAbstract)

    Sister module: enforces abstract classes.
    Pair with `Sub::Abstract` to create fully enforced abstract base classes.

- [Sub::Private](https://metacpan.org/pod/Sub%3A%3APrivate)

    Sister module enforcing strictly private (owner-only) access.

- [Sub::Protected](https://metacpan.org/pod/Sub%3A%3AProtected)

    Sister module enforcing protected (owner + subclass) access.

# PUBLIC VARIABLES

## `$BYPASS`

Set to a true value to disable the abstract-method croak for all wrapped
subs.  Use `local` in tests:

    local $Sub::Abstract::BYPASS = 1;

**Warning:** any truthy value (including strings like `"false"`, `"off"`,
`"no"`) enables bypass, because Perl's truthiness is not English.

## `%config`

- `harness_bypass` (default: 1)

    When true, the abstract-method croak is suppressed whenever
    `$ENV{HARNESS_ACTIVE}` is set (the convention used by [Test::Harness](https://metacpan.org/pod/Test%3A%3AHarness)/prove).
    Set to 0 to test enforcement from within a test harness.

    Note that `$BYPASS` takes precedence: see ["Bypass precedence"](#bypass-precedence) under
    KNOWN LIMITATIONS.

# AUTHOR

Nigel Horne, `<njh at nigelhorne.com>`

# LICENCE AND COPYRIGHT

Copyright 2026 Nigel Horne.

Usage is subject to the GPL2 licence terms.
If you use it, please let me know.
