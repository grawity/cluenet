#!perl
package Cluenet::Rpc::Client;
use warnings;
use strict;
use feature "say";
use feature "switch";
use base "Cluenet::Rpc";
use base "Exporter";
use Authen::SASL;
use Carp;
use Cluenet::Common;
use Cluenet::Kerberos;
use Cluenet::Rpc;
use IO::Handle;
use Sys::Hostname;

use constant {
	RPC_PORT	=> 10875,
	SASL_SERVICE	=> "host",
};

our @EXPORT = qw(
	RPC_PORT
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

sub DESTROY {}

sub connect {
	use IO::Socket::INET6;
	my ($self, $addr, $port) = @_;
	$addr //= hostname;
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

sub rpc_call {
	my ($self, $func, %args) = @_;
	$self->rpc_send([$func, \%args]);
	return $self->rpc_recv;
}

sub call {
	my ($self, $func, %args) = @_;
	my $reply = $self->rpc_call($func, %args);

	if ($self->{die_on_failure} && !$reply->{success}) {
		if ($reply->{err}) {
			chomp(my $err = join("\n", $reply->{err}));
			warn "$err\n";
		}
		die "\033[1;31mError: ".($reply->{msg} // "unknown error")."\033[m\n";
	}

	return $reply;
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	my ($name) = $Cluenet::Rpc::Client::AUTOLOAD =~ /.+::(.+?)$/;
	if ($self->{debug}) {
		warn "AUTOLOAD: $Cluenet::Rpc::Client::AUTOLOAD -> $name\n";
	}
	$self->call($name, @args);
}

sub authenticate {
	my ($self, $mech) = @_;

	if (defined $self->{sasl}) {
		return $self->{authreply};
	}

	$mech //= "GSSAPI";
	given (uc $mech) {
		krb5_ensure_tgt when "GSSAPI";
	}

	my $sasl = Authen::SASL->new(mech => $mech, callback => $self->{callbacks});
	$self->{sasl} = $sasl->client_new(SASL_SERVICE, $self->{host});

	my $reply = $self->call("auth",
		mech => $self->{sasl}->mechanism,
		data => b64_encode($self->{sasl}->client_start));

	while (exists $reply->{data}) {
		my $challenge = b64_decode($reply->{data});
		$reply = $self->call("auth",
			data => b64_encode($self->{sasl}->client_step($challenge)));
	}

	if ($reply->{success}) {
		$self->{seal} = 1;
		$self->{authreply} = $reply;
		if ($self->{verbose}) {
			warn "\033[32mAuthenticated as $reply->{authuser} (authorized for $reply->{user})\033[m\n";
		}
	}
	return $reply;
}

1;
