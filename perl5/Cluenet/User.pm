#!perl
package Cluenet::User;
use common::sense;
use Carp;

sub new {
	my ($class, $name) = @_;
	my $self = {};

	given ($name) {
		when (/^cn=(.+),ou=people,dc=cluenet,dc=org$/) {
			$self->{input} = "ldapdn";
			$name = $1;
		}
		when (/^\w+=/ or /,\w+=/) {
			croak "invalid DN '$name' given to ${class}->new";
			return undef;
		}
		when (/^(.+?)(?:\+(.+))?\@cluenet\.org$/) {
			$self->{input} = "email";
			$name = $1;
			$self->{mailbox} = $2;
		}
		when (/^(.+)\@(\S+)$/) {
			$self->{input} = "krbprinc";
		}
		default {
			$self->{input} = "name";
		}
	}

	if ($name =~ /^(.+)\@(.+)$/) {
		$name = $1;
		$self->{realm} = $2;
	} else {
		$self->{realm} = "CLUENET.ORG";
	}

	if ($self->{input} eq "ldapdn") {
		$self->{realm} = uc $self->{realm};
	}

	$self->{instance} = [split(m|/|, $name)];
	$self->{name} = shift($self->{instance});

	bless $self, $class;
}

sub name {
	my ($self) = @_;
	return $self->{name};
}

sub instance {
	my ($self) = @_;
	return @{$self->{instance}};
}

sub namei {
	my ($self) = @_;
	return join("/", $self->name, $self->instance);
}

sub realm {
	my ($self) = @_;
	return $self->{realm};
}

sub ldapdn {
	my ($self) = @_;
	my $u = $self->namei;
	if ($self->realm ne "CLUENET.ORG") {
		$u .= "\@".lc($self->realm);
	}
	return "cn=$u,ou=people,dc=cluenet,dc=org";
}

sub krbname {
	my ($self) = @_;
	if ($self->realm eq "CLUENET.ORG") {
		return $self->namei;
	} else {
		return join("\@", $self->namei, $self->realm);
	}
}

sub krbprinc {
	my ($self) = @_;
	return join("\@", $self->namei, $self->realm);
}

1;
