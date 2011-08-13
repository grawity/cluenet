#!perl
package Cluenet::Rpc::Client;
use parent 'Cluenet::Rpc';
use parent 'Exporter';
use common::sense;
use Authen::SASL "XS";
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

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{raise} = 0;
	$self->{user} = undef;
	return $self;
}

sub AUTOLOAD {
	our $AUTOLOAD;
	my ($self, @args) = @_;
	my ($name) = $AUTOLOAD =~ /.+::(.+?)$/;
	$self->call($name, @args);
}

sub DESTROY {}

sub connect {
	use IO::Socket::INET6;
	my ($self, $addr, $port) = @_;
	$addr //= hostname;
	$port ||= RPC_PORT;
	my $sock = IO::Socket::INET6->new(
			PeerAddr => $addr,
			PeerPort => $port,
			Proto => "tcp")
		or die "RPC: connect($addr, $port) failed: $!\n";
	$sock->autoflush(0);
	$self->{rfd} = $sock;
	$self->{wfd} = $sock;
	$self->{rhost} = $addr;
}

sub rpc_call {
	my ($self, $func, %args) = @_;
	$self->rpc_send([$func, \%args]);
	return $self->rpc_recv;
}

sub call {
	my ($self, $func, %args) = @_;
	my $reply = $self->rpc_call($func, %args);
	if ($self->{raise} && !$reply->{success}) {
		die "error: ".($reply->{msg} // "unknown error")."\n";
	}
	return $reply;
}

sub authenticate {
	my ($self, $mech) = @_;

	if (defined $self->{authreply}) {
		return $self->{authreply};
	}

	$mech //= "GSSAPI";
	given (uc $mech) {
		krb5_ensure_tgt when "GSSAPI";
	}

	my %callbacks = (
		user => sub { $self->{user} // getlogin },
	);

	my $sasl = Authen::SASL->new(mechanism => $mech, callback => \%callbacks);
	my $conn = $sasl->client_new(SASL_SERVICE, $self->{rhost});
	$self->{sasl} = $conn;

	my $reply = $self->auth(mech => $conn->mechanism,
				data => b64_encode($conn->client_start),
				seal => 1);

	while ($conn->need_step) {
		my $challenge = b64_decode($reply->{data});
		$reply = $self->auth(data => b64_encode($conn->client_step($challenge)));
	}

	if ($reply->{success}) {
		$self->{authreply} = $reply;
		if ($self->{verbose}) {
			warn "\033[32mAuthenticated as $reply->{authuser} (authorized for $reply->{user})\033[m\n";
		}
		$self->{seal} = $reply->{seal} // 1;
	}
	return $reply;
}

1;
