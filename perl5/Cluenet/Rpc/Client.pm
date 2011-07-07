#!perl
package Cluenet::Rpc::Client;
use warnings;
use strict;
use feature "say";
use feature "switch";
use base "Cluenet::Rpc";
use base "Exporter";
use Authen::SASL;
use Cluenet::Common;
use Cluenet::Kerberos;
use Cluenet::Rpc;
use IO::Handle;

use constant {
	RPC_PORT	=> 10875,
	SASL_SERVICE	=> "host",
};

our @EXPORT = qw(
	RPC_PORT
	check
	);

sub new {
	my $self = {
		callbacks	=> {
			user => sub { getlogin },
		},
		debug		=> $ENV{DEBUG} // 0,
		die_on_failure	=> 0,
	};
	bless $self, shift;
}

sub connect {
	use IO::Socket::INET6;
	my ($self, $addr, $port) = @_;
	$addr //= getfqdn;
	$port //= RPC_PORT;

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
	my $reply = $self->rpc_recv;
	if ($self->{die_on_failure}) {
		check $reply;
	}
	return $reply;
}

sub check {
	my $r = shift;
	if (!$r->{status}) {
		if ($r->{error}) {
			chomp(my $err = join("\n", $r->{error}));
			warn "$err\n";
		}
		die "\033[1;31mError: ".($r->{msg} // "unknown error")."\033[m\n";
	}
}

sub authenticate {
	my ($self, $mech) = @_;
	$mech //= "GSSAPI";

	given (uc $mech) {
		when ("GSSAPI") {
			krb5_ensure_tgt;
		}
	}

	my $reply = $self->_sasl_step($mech);
	until (defined $reply->{status}) {
		$reply = $self->_sasl_step($reply->{data});
	}
	if ($reply->{status}) {
		$self->{seal} = 1;
		if ($self->{verbose}) {
			warn "\033[32mAuthenticated as $reply->{authuser} (authorized for $reply->{user})\033[m\n";
		}
	}
	return $reply;
}

sub _sasl_step {
	my $self = shift;
	my $req;
	if (!defined $self->{sasl}) {
		my $mech = shift;
		$self->{sasl} = Authen::SASL->new(
					mech => $mech,
					callback => $self->{callbacks},
				)->client_new(SASL_SERVICE, $self->{host});

		$req = {cmd => "auth"};
		$req->{mech} = $self->{sasl}->mechanism;
		$req->{data} = b64_encode($self->{sasl}->client_start);
	}
	else {
		my $data = b64_decode(shift);
		$req = {cmd => "auth"};
		$req->{data} = b64_encode($self->{sasl}->client_step($data));
	}

	if ($self->{sasl}->code < 0) {
		return {failure, msg => ($self->{sasl}->error)[1]};
	}
	return $self->request($req);
}

1;
