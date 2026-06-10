#!/usr/bin/perl
# t/locales.t -- locale-invariance tests for Sub::Abstract.
#
# -----------------------------------------------------------------------
# GeoIP DIMENSION (not applicable)
# -----------------------------------------------------------------------
# Sub::Abstract has no geographic access-control logic and performs no
# country detection.  Country-based (GeoIP) testing is not applicable to
# this module.  Only the POSIX system-locale dimension is tested here.
#
# -----------------------------------------------------------------------
# POSIX LOCALE DIMENSION
# -----------------------------------------------------------------------
# Sub::Abstract error messages are constructed entirely from:
#   - ASCII string literals embedded in the source
#   - Perl package names and method names (always ASCII in practice)
# They contain NO OS error strings ($!, POSIX::strerror) and use NO
# locale-sensitive formatting functions.  Therefore the croak output
# must be bitwise-identical regardless of the process locale.
#
# This file verifies that invariance holds under:
#   - en_US.UTF-8  (English, US)
#   - de_DE.UTF-8  (German)
#   - zh_CN.UTF-8  (Mandarin Chinese)
#
# If a locale is not installed on the test machine POSIX::setlocale()
# returns undef; the subtest notes this and verifies the message is at
# least defined rather than skipping entirely.
#
# Technique for locale-sensitive $! messages (not needed here, but
# shown as the correct pattern for reference):
#   use POSIX qw();
#   local $! = POSIX::ENOENT();
#   my $expected_msg = "$!";   # Perl's own $! layer in current locale
# Never use POSIX::strerror(ENOENT) -- it may diverge from Perl's $! on
# mixed-locale systems.

use strict;
use warnings;

# Add local lib and dev copies of test helpers to @INC.
BEGIN {
	my ($home) = ($ENV{HOME} =~ /\A(.+)\z/ms);
	unshift @INC,
		'lib',
		"$home/src/njh/Test-Mockingbird/lib",
		"$home/src/njh/Test-Returns/lib";
}

use Test::Most;
use POSIX qw(setlocale LC_ALL);
use Readonly;

# Load at compile time so the CHECK block fires correctly and $_post_check
# is set before any fixture packages call import().  use_ok() runs inside a
# runtime string-eval and would prevent the CHECK block from executing,
# leaving $post_check=0 and all wrappers stranded in @_pending forever.
use Sub::Abstract;
ok(1, 'Sub::Abstract loaded');

# ---------------------------------------------------------------------------
# Configuration -- no magic strings
# ---------------------------------------------------------------------------

# The three locale strings to test under.
Readonly::Array my @LOCALES => (
	'en_US.UTF-8',
	'de_DE.UTF-8',
	'zh_CN.UTF-8',
);

# Package and method names used in fixture classes.
my %config = (
	base_pkg   => 'LOC::Base',
	impl_pkg   => 'LOC::Impl',
	method     => 'locale_op',
	impl_value => 'done',
);

# ---------------------------------------------------------------------------
# Fixture packages (defined here; import() runs post-CHECK)
# ---------------------------------------------------------------------------

# LOC::Base: one abstract method installed post-CHECK via import().
{
	package LOC::Base;
	sub new { bless {}, shift }
	Sub::Abstract->import('locale_op');
}

# LOC::Impl satisfies the abstract contract.
{
	package LOC::Impl;
	our @ISA = ('LOC::Base');
	sub new       { bless {}, shift }
	sub locale_op { 'done' }
}

diag 'Collecting reference error message under default locale'
	if $ENV{TEST_VERBOSE};

# ---------------------------------------------------------------------------
# Helper: strip Carp stack trace, leaving only the core message text.
# ---------------------------------------------------------------------------
# Carp::croak appends " at FILE line N.\n\tCaller..." to the message.
# The stack trace includes object memory addresses and line numbers that
# vary between call sites and object instances.  Only the core text
# (everything before " at ") is locale-invariant and meaningful to compare.

sub _core_msg {
	my ($full) = @_;
	return q{} unless defined $full;
	# Strip from the first " at <non-space> line <digits>" onward.
	(my $core = $full) =~ s/ at \S+ line \d+\..*\z//s;
	return $core;
}

# The expected core message pattern: locale-invariant ASCII text only.
Readonly::Scalar my $EXPECTED_CORE =>
	"$config{method}() is an abstract method of $config{base_pkg}"
	. " and must be implemented by $config{base_pkg}";

# ---------------------------------------------------------------------------
# Sanity subtest: default locale produces the expected core message.
# ---------------------------------------------------------------------------

subtest 'reference message has correct format under default locale' => sub {
	plan tests => 3;

	# Disable both bypass paths so the wrapper fires.
	my $msg;
	{
		local $Sub::Abstract::BYPASS                 = 0;
		local $Sub::Abstract::config{harness_bypass} = 0;
		local $ENV{HARNESS_ACTIVE}                   = 0;

		# Invoke the abstract method; capture the croak text.
		eval { LOC::Base->new->locale_op };
		$msg = $@;
	}

	diag "Reference message (full): $msg" if $ENV{TEST_VERBOSE};
	diag "Reference message (core): " . _core_msg($msg) if $ENV{TEST_VERBOSE};

	ok defined($msg) && length($msg),
		'reference message is defined and non-empty';

	# The core text must match the expected ASCII pattern.
	like _core_msg($msg),
		qr/\Q$config{method}\E\(\) is an abstract method of \Q$config{base_pkg}\E/,
		'reference message contains method name and owner package';

	like _core_msg($msg),
		qr/must be implemented by \Q$config{base_pkg}\E/,
		'reference message contains invocant class name';
};

# ---------------------------------------------------------------------------
# POSIX locale tests: core message must be identical under each locale.
# ---------------------------------------------------------------------------
# Strategy: strip the Carp stack trace and compare only the core text.
# The stack trace contains addresses and line numbers that differ per call
# site; the core text is the only part that could change with locale.

for my $locale (@LOCALES) {

	subtest "error message core is locale-invariant under $locale" => sub {
		plan tests => 2;

		diag "Testing under locale: $locale" if $ENV{TEST_VERBOSE};

		# Save current locale; restore unconditionally at end of subtest.
		my $saved_locale = setlocale(LC_ALL);
		my $locale_ok    = setlocale(LC_ALL, $locale);

		unless (defined $locale_ok) {
			diag "Locale $locale not installed on this system";
		}

		# Capture the croak under this locale (or the unchanged locale).
		my $msg;
		{
			local $Sub::Abstract::BYPASS                 = 0;
			local $Sub::Abstract::config{harness_bypass} = 0;
			local $ENV{HARNESS_ACTIVE}                   = 0;

			eval { LOC::Base->new->locale_op };
			$msg = $@;
		}

		diag "Core message under $locale: " . _core_msg($msg)
			if $ENV{TEST_VERBOSE};

		ok defined($msg) && length($msg),
			"error message is defined and non-empty under $locale";

		# Compare only the core text; the stack trace is not locale-sensitive.
		if (defined $locale_ok) {
			is _core_msg($msg), $EXPECTED_CORE,
				"core message is identical to expected text under $locale";
		}
		else {
			# Locale unavailable: just verify the core text looks right.
			like _core_msg($msg),
				qr/\Q$config{method}\E\(\) is an abstract method/,
				"core message matches expected pattern (locale unavailable: $locale)";
		}

		# Restore the locale so subsequent subtests start from a clean state.
		setlocale(LC_ALL, $saved_locale) if defined $saved_locale;
	};
}

# ---------------------------------------------------------------------------
# Implementing subclass is unaffected by locale changes
# ---------------------------------------------------------------------------

subtest 'implementing subclass returns correctly under all locales' => sub {
	plan tests => scalar @LOCALES;

	for my $locale (@LOCALES) {
		my $saved = setlocale(LC_ALL);
		setlocale(LC_ALL, $locale);    # best-effort; ignore failure

		# LOC::Impl satisfies the contract; should never croak.
		my $result;
		lives_ok { $result = LOC::Impl->new->locale_op }
			"LOC::Impl->locale_op lives under $locale";

		setlocale(LC_ALL, $saved) if defined $saved;
	}
};

done_testing;
