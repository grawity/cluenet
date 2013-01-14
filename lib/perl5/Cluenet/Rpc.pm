#!perl
use warnings;
use strict;

package Cluenet::Rpc;

use base "Exporter";
use MIME::Base64;

our @EXPORT = qw(
	b64_encode
	b64_decode
);

our $DEBUG = $ENV{DEBUG};

sub b64_encode { MIME::Base64::encode_base64(shift // "", "") }
sub b64_decode { MIME::Base64::decode_base64(shift // "") }

package Cluenet::Rpc::Connection;

use Carp;
use IO::Handle;
use JSON;

my $JSON = JSON->new->allow_nonref(1);

sub new {
	my ($class, $rfd, $wfd) = @_;
	my $self = {
		rfd	=> $rfd,
		wfd	=> $wfd // $rfd,
		encoder	=> undef,
		decoder	=> undef,
	};
	binmode $self->{rfd}, ":raw";
	binmode $self->{wfd}, ":raw";
	$self->{wfd}->autoflush(0);
	bless $self, $class;
}

sub close {
	my ($self) = @_;
	$self->{wfd}->close;
	$self->{rfd}->close;
}

sub send_packed {
	my ($self, $buf) = @_;
	$self->{wfd}->printf('NullRPC:%08x', length($buf));
	$self->{wfd}->print($buf);
	$self->{wfd}->flush();
}

sub recv_packed {
	my ($self) = @_;
	my ($len, $buf);
	$len = $self->{rfd}->read($buf, 16);
	unless (defined $len) {
		croak "RPC: read error: $!";
		return undef;
	}
	if ($len == 0) {
		return undef;
	}
	unless ($len == 16 && $buf =~ /^NullRPC:[0-9a-f]{8}$/) {
		$self->{wfd}->print("Protocol mismatch.\n");
		$self->close;
		croak "RPC: protocol mismatch, received ".serialize($buf);
		return undef;
	}
	$len = hex(substr($buf, 8));
	unless ($self->{rfd}->read($buf, $len) == $len) {
		croak "RPC: short read (".length($buf)." bytes out of $len)";
		return undef;
	}
	return $buf;
}

sub serialize {
	return $JSON->encode(shift // {});
}

sub unserialize {
	return $JSON->decode(shift || '{}');
}

sub send {
	my ($self, $obj) = @_;
	my $buf = serialize($obj);
	$Cluenet::Rpc::DEBUG and warn "RPC: --> $buf\n";
	if ($self->{decoder}) {
		$buf = $self->{decoder}->($self, $buf);
	}
	$self->send_packed($buf);
}

sub recv {
	my ($self) = @_;
	my $buf = $self->recv_packed();
	if (!defined $buf) {
		return undef;
	}
	if ($self->{encoder}) {
		$buf = $self->{encoder}->($self, $buf);
	}
	$Cluenet::Rpc::DEBUG and warn "RPC: <-- $buf\n";
	return unserialize($buf);
}

package Cluenet::Rpc::Server;

use Carp;

our %methods;

sub success { status => 1 };
sub failure { status => 0 };

sub new {
	my ($class, $conn) = @_;
	our $methods;
	my $self = {
		conn => $conn,
		methods => $methods,
		state => {},
	};
	bless $self, $class;
}

sub connect_fds {
	my ($self, $rfd, $wfd) = @_;
	$self->{conn} = Cluenet::Rpc::Connection->new($rfd, $wfd);
}

sub connect_stdio {
	my ($self) = @_;
	$self->connect_fds(\*STDIN, \*STDOUT);
}

sub call {
	my ($self, $req) = @_;
	unless (ref $req eq 'HASH') {
		return {err => "type mismatch (input must be a hash)"};
	}
	my $method = $req->{method};
	my $args = $req->{args};
	unless (defined $method && defined $args) {
		return {err => "missing argument"};
	}
	unless (ref $method eq '' && ref $args eq 'ARRAY') {
		return {err => "type mismatch"};
	}
	my $func = $self->{methods}{$method};
	unless (ref $func eq 'CODE') {
		return {err => "unknown method"};
	}
	my $ret = eval {$func->($self->{state}, @$args)};
	if ($@) {
		return {err => "internal error: $@"};
	} else {
		return {data => $ret};
	}
}

sub loop {
	my ($self) = @_;
	if (!$self->{conn}) {
		croak "Starting main loop without a connection";
	}
	while (my $in = $self->{conn}->recv) {
		my $out = $self->call($in);
		$self->{conn}->send($out);
		last if $self->{eof};
	}
}

sub stop {
	my ($self) = @_;
	$self->{eof} = 1;
}

package Cluenet::Rpc::Client;

use Authen::SASL;
use Carp;
use Data::Dumper;
use IO::Socket::INET6;

Cluenet::Rpc->import;

sub new {
	my ($class, %args) = @_;
	my $self = {
		conn => undef,
		%args,
	};
	bless $self, $class;
}

sub connect_tcp {
	my ($self, $addr, $port) = @_;
	unless (defined $addr && defined $port) {
		croak "Undefined \$addr or \$port";
	}
	my $sock = IO::Socket::INET6->new(
			PeerAddr => $addr,
			PeerPort => $port,
			Proto => "tcp");
	if (!$sock) {
		croak "RPC: connect($addr, $port) failed: $!";
	}
	$sock->autoflush(0);
	$self->{addr} = $addr;
	$self->{conn} = Cluenet::Rpc::Connection->new($sock);
}

sub _rawcall {
	my ($self, $out) = @_;
	$self->{conn}->send($out);
	$self->{conn}->recv;
}

sub rawcall {
	my ($self, $method, $args) = @_;
	my $out = {method => $method, args => $args};
	my $in = $self->_rawcall($out);
	if (exists $in->{err}) {
		croak "RPC: call failed: $in->{err}\n";
	} elsif (exists $in->{data}) {
		return $in->{data};
	} else {
		croak "RPC: protocol error: return value has neither 'err' nor 'data'\n";
	}
}

sub call {
	my ($self, $method, @args) = @_;
	$self->rawcall($method, \@args);
}

=foo
sub AUTOLOAD {
	my ($self, @args) = @_;
	my ($name) = (our $AUTOLOAD =~ /.+::(.+?)$/);
	if ($name =~ /^_/) {
		croak "Attempted to autoload a private method '$name'";
	}
	print Dumper($self);
	$self->call($name, @args);
}
=cut

sub DESTROY {}

sub authenticate {
	my ($self, $mech, %args) = @_;

	if (defined $self->{auth}) {
		return $self->{auth};
	}

	if (!defined $mech) {
		my $reply = $self->call("authenticate", mech => undef);
		$mech = shift($reply->{data}{mechanisms});
	}
	my $callbacks = $self->{sasl_callbacks};
	$callbacks->{user} //= sub { getlogin };
	my $sasl = Authen::SASL->new(mech => $mech, callback => $callbacks);
	$self->{sasl_obj} = $sasl->client_new($self->{sasl_service}, $self->{addr});

	my $outbuf = $self->{sasl_obj}->client_start;
	my $reply = $self->call("authenticate", mech => $self->{sasl_obj}->mechanism,
						data => b64_encode($outbuf));
	until ($reply->{finished}) {
		my $inbuf = b64_decode($reply->{data});
		my $outbuf = $self->{sasl_obj}->client_step($inbuf);
		$reply = $self->call("authenticate", data => b64_encode($outbuf));
	}
	if ($reply->{success}) {
		$self->{auth} = $reply;
	}
	return $reply;
}

1;
