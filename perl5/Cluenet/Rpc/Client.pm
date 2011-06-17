#!perl
package Cluenet::Rpc::Client;
use warnings;
use strict;
use feature "say";
use base "Cluenet::Rpc";
use Authen::SASL;
use Cluenet::Common;
use Cluenet::Rpc;
use IO::Handle;

use constant SASL_SERVICE => "host";

sub new { bless {}, shift; }

sub connect_stdio {
	my $self = shift;
	$self->{infd} = \*STDIN;
	$self->{outfd} = \*STDOUT;
	$self->{host} = getfqdn;
}

sub connect_spawn {
	use IPC::Open2;
	my $self = shift;
	$self->{pid} = open2($self->{infd}, $self->{outfd}, "./cluerpcd");
	$self->{host} = getfqdn;
}

sub connect_socket {
	use IO::Socket::INET6;
	my ($self, $addr, $port) = @_;
	$addr //= getfqdn;
	$port //= "cluerpc";

	my $sock = IO::Socket::INET6->new(
			PeerAddr => $addr,
			PeerPort => $port,
			Proto => "tcp")
			or die "connect($addr, $port) failed: $!\n";
	$sock->autoflush(0);
	$self->{infd} = $sock;
	$self->{outfd} = $sock;
	$self->{host} = $addr;
}

sub request {
	my $self = shift;
	$self->rpc_send(ref $_[0] ? $_[0] : {@_});
	return $self->rpc_recv;
}

sub authenticate {
	my ($self, %args) = @_;
	$args{mech} //= "GSSAPI";
	$args{seal} //= 1;

	my $reply = $self->sasl_step($args{mech}, %args);
	until (defined $reply->{status}) {
		$reply = $self->sasl_step(b64_decode($reply->{data}));
	}
	if ($reply->{status}) {
		$self->{seal} = $reply->{seal} // 0;
		if ($self->{verbose}) {
			say "\033[32mAuthenticated as $reply->{user} (authorized for $reply->{authzid})\033[m";
		}
	}
	return $reply;
}

sub sasl_step {
	my $self = shift;
	my $req;
	if (!defined $self->{sasl}) {
		my ($mech, %args) = @_;
		$self->{sasl} = Authen::SASL->new(
					mech => $mech,
					callback => $self->{callbacks},
				)->client_new(SASL_SERVICE, $self->{host});

		$req = {cmd => "auth", %args};
		$req->{mech} = $self->{sasl}->mechanism;
		$req->{data} = b64_encode($self->{sasl}->client_start);
	}
	else {
		my ($data) = @_;
		$req = {cmd => "auth"};
		$req->{data} = b64_encode($self->{sasl}->client_step($data));
	}

	if ($self->{sasl}->code < 0) {
		return {failure, msg => join(" ", $self->{sasl}->error)};
	}
	return $self->request($req);
}

1;
