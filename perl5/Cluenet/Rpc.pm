#!perl
=protocol

Basic structure:

	char magic[4]		= "!rpc"
	char length[4]		= data length in hexadecimal
	char data[length]	= RPC data

=cut

package Cluenet::Rpc;
use parent 'Exporter';
use common::sense;
use Carp;
use IO::Handle;
use JSON;
use MIME::Base64;

our @EXPORT = qw(
	b64_encode
	b64_decode
	failure
	success
);

our $DEBUG = $ENV{DEBUG};

sub failure	{ success => 0 }
sub success	{ success => 1 }

sub b64_encode	{ MIME::Base64::encode_base64(shift // "", "") }
sub b64_decode	{ MIME::Base64::decode_base64(shift // "") }

sub new {
	my ($class, $rfd, $wfd) = @_;
	my $self = {
		rfd => $rfd // \*STDIN,
		wfd => $wfd // $rfd // \*STDOUT,
	};
	binmode $self->{rfd}, ":raw";
	binmode $self->{wfd}, ":raw";
	bless $self, $class;
}

sub close {
	my ($self) = @_;
	$self->{rfd}->close;
	$self->{wfd}->close;
}

# send/receive binary data

sub rpc_send_packed {
	my ($self, $buf) = @_;
	$self->{wfd}->printf('!rpc%04x', length($buf));
	$self->{wfd}->print($buf);
	$self->{wfd}->flush;
}

sub rpc_recv_packed {
	my ($self) = @_;
	my ($len, $buf);
	unless ($self->{rfd}->read($buf, 8) == 8) {
		return undef;
	}
	unless ($buf =~ /^!rpc[0-9a-f]{4}$/) {
		chomp($buf .= $self->{rfd}->getline);
		$self->{wfd}->print("Protocol mismatch.\n");
		$self->close;
		croak "RPC: protocol mismatch, received '$buf'";
		return undef;
	}
	$len = hex(substr($buf, 4));
	unless ($self->{rfd}->read($buf, $len) == $len) {
		return undef;
	}
	return $buf;
}

# send/receive Perl objects

sub rpc_serialize {
	return encode_json(shift // {});
}

sub rpc_unserialize {
	return decode_json(shift || '{}');
}

sub rpc_send {
	my ($self, $obj) = @_;
	my $buf = rpc_serialize($obj);
	$DEBUG and warn "RPC: --> $buf\n";
	if ($self->{seal}) {
		$buf = $self->{sasl}->encode($buf);
	}
	$self->rpc_send_packed($buf);
}

sub rpc_recv {
	my ($self) = @_;
	my $buf = $self->rpc_recv_packed;
	if (!defined $buf) {
		return {failure, msg => "connection closed while reading"};
	}
	if ($self->{seal}) {
		$buf = $self->{sasl}->decode($buf);
	}
	$DEBUG and warn "RPC: <-- $buf\n";
	return rpc_unserialize($buf);
}

1;
