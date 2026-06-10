use strict;
use warnings;
use Test::Most;
use Sub::Abstract;

# Edge cases: both forms produce identical behaviour, invocant determination,
# class-method call, function-style call, multiple abstract methods independent.

local $ENV{HARNESS_ACTIVE}   = 0;
local $Sub::Abstract::BYPASS = 0;

# ---- Attribute form and declarative form are equivalent ----

{
	package AttrBase;
	use Sub::Abstract;
	sub new   { bless {}, shift }
	sub greet :Abstract { }
}

{
	package DeclBase;
	use Sub::Abstract qw(greet);
	sub new { bless {}, shift }
}

{
	package Outsider;
	sub probe_attr { AttrBase->new->greet }
	sub probe_decl { DeclBase->new->greet }
}

throws_ok { Outsider::probe_attr() } qr/abstract method/, 'attr form: unimplemented: croaks';
throws_ok { Outsider::probe_decl() } qr/abstract method/, 'decl form: unimplemented: croaks';

# ---- Function-style call (no object): invocant is the package name ----

throws_ok { AttrBase::greet(AttrBase->new) }
	qr/\Qgreet() is an abstract method of AttrBase and must be implemented by AttrBase\E/,
	'function-style call: invocant resolved from $_[0] (blessed ref)';

throws_ok { AttrBase::greet('AttrBase') }
	qr/\Qgreet() is an abstract method of AttrBase and must be implemented by AttrBase\E/,
	'function-style call with bare class name: invocant is the string';

# ---- ref($_[0])||$_[0]: unblessed invocant is the string itself ----

throws_ok { AttrBase->greet }
	qr/\Qgreet() is an abstract method of AttrBase and must be implemented by AttrBase\E/,
	'class-method call: invocant is the class name string';

# ---- Two independently wrapped subs enforce independently ----

{
	package Multi;
	use Sub::Abstract;
	sub new { bless {}, shift }
	sub foo :Abstract { }
	sub bar :Abstract { }
}

{
	package MultiImpl;
	our @ISA = ('Multi');
	sub new { bless {}, shift }
	sub foo { 'foo-val' }
	# bar not implemented
}

lives_and { is(MultiImpl->new->foo, 'foo-val') }
	'multi: implemented sub works';

throws_ok { MultiImpl->new->bar }
	qr/\Qbar() is an abstract method of Multi and must be implemented by MultiImpl\E/,
	'multi: unimplemented sub still croaks independently';

# ---- Abstract method with no arguments (class method, no invocant in @_) ----

{
	package NoArg;
	use Sub::Abstract qw(class_op);
	sub new { bless {}, shift }
}

# Calling with undef as $_[0]: ref(undef)||undef -> '' (empty string)
throws_ok { NoArg::class_op(undef) }
	qr/abstract method/,
	'abstract wrapper tolerates undef as invocant (no crash)';

done_testing;
