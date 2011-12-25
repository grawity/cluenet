#!perl
package Cluenet::Rpc::Client;
use parent 'Cluenet::Rpc';
use parent 'Exporter';
use common::sense;
use Authen::SASL;
use Carp;
use Cluenet::Rpc;
use IO::Handle;
use Sys::Hostname;

use constant {
	RPC_TCP_PORT	=> 10875,
	SASL_SERVICE	=> "host",
};

## Basic RPC client proxy object

sub new {
	my ($class, %args) = @_;

	my $self = $class->SUPER::new(@_);
	$self->{raise_errors}	= $args{raise_errors} // 0;
	$self->{sasl_service}	= $args{sasl_service} // SASL_SERVICE;
	return $self;
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	our $AUTOLOAD;

	my ($name) = ($AUTOLOAD =~ /.+::(.+?)$/);
	$self->call($name, @args);
}

sub DESTROY {}

sub rpc_call {
	my ($self, $func, %args) = @_;

	$self->rpc_send([$func, \%args]);
	return $self->rpc_recv;
}

sub call {
	my ($self, $func, %args) = @_;

	my $reply = $self->rpc_call($func, %args);
	if (!$reply->{success} && $self->{raise_errors}) {
		croak "error: ".($reply->{error} // "unknown error");
	}
	return $reply;
}

sub authenticate {
	my ($self, $mech, %args) = @_;
	$mech //= "GSSAPI";
	
	if (defined $self->{auth_info}) {
		return $self->{auth_info};
	}

	my %callbacks = (
		user => sub { $args{user} // getlogin },
	);
	my $sasl = Authen::SASL->new(mechanism => $mech, callback => \%callbacks);
	$self->{sasl} = $sasl->client_new($self->{sasl_service}, $self->{remote_host});

	my $outbuf = $self->{sasl}->client_start;
	my $reply = $self->auth(mech => $self->{sasl}->mechanism,
				data => b64_encode($outbuf),
				seal => $args{seal} // 1);

	until ($reply->{finished}) {
		my $inbuf = b64_decode($reply->{data});
		my $outbuf = $self->{sasl}->client_step($inbuf);
		$reply = $self->auth(data => b64_encode($outbuf));
	}

	if ($reply->{success}) {
		$self->{auth_info} = $reply;
		if ($self->{verbose}) {
			warn "\033[32mAuthenticated as $reply->{authuser} (authorized for $reply->{user})\033[m\n";
		}
		$self->{seal} = $reply->{seal} // 1;
	}
	return $reply;
}

## TCP client

sub connect {
	use IO::Socket::INET6;
	my ($self, $addr, $port) = @_;
	$addr //= hostname;
	$port ||= RPC_TCP_PORT;

	$self->{remote_host} = $addr;

	my $sock = IO::Socket::INET6->new(
			PeerAddr => $addr,
			PeerPort => $port,
			Proto => "tcp")
		or die "RPC: connect($addr, $port) failed: $!\n";
	$sock->autoflush(0);
	$self->{rfd} = $sock;
	$self->{wfd} = $sock;
}

1;
