#!perl
package Cluenet::Rpc::Client;
use common::sense;
use Authen::SASL;
use Carp;
use Cluenet::Rpc;
use Cluenet::Rpc::Connection;
use IO::Socket::INET6;

sub new {
	my ($class, %args) = @_;
	my $self = {
		connection	=> undef,
		remote_host	=> undef,
		sasl_service	=> "host",
		raise_errors	=> 0,
		sasl_callbacks	=> {},
		next_call_id	=> 0,
		%args,
	};
	bless $self, $class;
}

sub connect {
	my ($self, $addr, $port) = @_;

	unless (defined $addr && defined $port) {
		croak "Undefined \$addr or \$port";
	}

	my $sock = IO::Socket::INET6->new(
			PeerAddr => $addr,
			PeerPort => $port,
			Proto => "tcp");
	$sock or croak "RPC: connect($addr, $port) failed: $!\n";
	$sock->autoflush(0);

	$self->{remote_host} = $addr;
	$self->{connection} = Cluenet::Rpc::Connection->new($sock);
}

sub callraw {
	my ($self, $req) = @_;
	$self->{connection}->send($req);
	$self->{connection}->recv();
}

sub callfunc {
	my ($self, $method, @args) = @_;
	my $req = {method => $method, args => \@args};
	my $rep = $self->callraw($req);
	if (!$rep->{success} and $self->{raise_errors}) {
		die "RPC: failure: $rep->{error}\n";
	}
	return $rep;
}

sub authenticate {
	my ($self, $mech, %args) = @_;
	
	if (defined $self->{auth_info}) {
		return $self->{auth_info};
	}

	if (!defined $mech) {
		$mech = "GSSAPI";
=todo
		my $reply = $self->callfunc("authenticate",
					mech => undef);
		$mech = shift($reply->{mechanisms});
=cut
	}

	my $callbacks = $self->{sasl_callbacks};

	$callbacks->{user} //= sub { getlogin };

	my $sasl = Authen::SASL->new(mechanism => $mech, callback => $callbacks);
	$self->{sasl_obj} = $sasl->client_new($self->{sasl_service}, $self->{remote_host});

	my $outbuf = $self->{sasl_obj}->client_start;
	my $reply = $self->callfunc("authenticate",
				mech => $self->{sasl_obj}->mechanism,
				data => b64_encode($outbuf));

	until ($reply->{finished}) {
		my $inbuf = b64_decode($reply->{data});
		my $outbuf = $self->{sasl_obj}->client_step($inbuf);
		$reply = $self->callfunc("authenticate",
				data => b64_encode($outbuf));
	}

	if ($reply->{success}) {
		$self->{auth_info} = $reply;
	}
	return $reply;
}

sub whoami {
	my ($self) = @_;
	$self->{auth_info};
}

sub AUTOLOAD {
	my ($self, @args) = @_;

	my ($name) = (our $AUTOLOAD =~ /.+::(.+?)$/);
	if ($name =~ /^_/) {
		croak "Attempted to autoload a private method '$name'";
	}

	$self->callfunc($name, @args);
}

sub DESTROY {}

1;
