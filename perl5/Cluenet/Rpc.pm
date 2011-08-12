#!perl
package Cluenet::Rpc;
# ClueRPC transport layer

use warnings;
use strict;
use base "Exporter";
use feature "say";
use Carp;
use IO::Handle;
use JSON;
use MIME::Base64;

our @EXPORT = qw(
	b64_encode
	b64_decode
	failure
	success
	rpc_encode
	rpc_decode
	);

=protocol

Basic structure:

	char magic[4]		= "!rpc"
	char length[4]		= data length in hexadecimal
	char data[length]	= RPC data

If negotiated during authentication, data is encrypted using sasl_encode().

Data is a JSON-encoded hash.

	Requests:
		[$funcname, {%args}]
	
	Success replies:
		{status => 1, %data}
	
	Failure replies:
		{status => 0, msg => "description"}

=cut

sub failure { success => 0 }
sub success { success => 1 }

sub rpc_encode { encode_json(shift // {}); }
sub rpc_decode { decode_json(shift || '{}'); }

sub b64_encode { MIME::Base64::encode_base64(shift // "", "") }
sub b64_decode { MIME::Base64::decode_base64(shift // "") }

# send/receive binary data

sub rpc_send_packed {
	my ($fd, $buf) = @_;

	$fd->printf("!rpc%04x", length($buf));
	$fd->write($buf, length($buf));
	$fd->flush;
}

sub rpc_recv_packed {
	my $fd = shift;

	my ($len, $buf);
	# read magic+length
	unless ($fd->read($buf, 8) == 8) {
		return undef;
	}
	# check magic number to avoid parsing Perl errors
	unless (substr($buf, 0, 4) eq "!rpc") {
		$buf .= $fd->getline;
		$buf .= "\n" unless $buf =~ /\n$/s;
		die "Invalid data received:\n$buf";
	}
	# read data
	$len = hex(substr($buf, 4));
	unless ($fd->read($buf, $len) == $len) {
		return undef;
	}
	return $buf;
}

# send/receive Perl objects

sub rpc_send {
	my ($self, $data) = @_;

	my $buf = rpc_encode($data);
	$self->{debug} and warn "SEND: $buf\n";
	if ($self->{seal}) {
		$buf = $self->{sasl}->encode($buf);
	}
	rpc_send_packed($self->{outfd}, $buf);
}

sub rpc_recv {
	my $self = shift;

	my $buf = rpc_recv_packed($self->{infd});
	if (!defined $buf) {
		return {failure, msg => "connection closed while reading"};
	}
	if ($self->{seal}) {
		$buf = $self->{sasl}->decode($buf);
	}
	$self->{debug} and warn "RECV: $buf\n";
	return rpc_decode($buf);
}

# send/receive Perl objects over stdio

sub rpc_send_fd {
	my ($data, $fd) = @_;

	my $buf = rpc_encode($data);
	rpc_send_packed($fd // *STDOUT, $buf);
}

sub rpc_recv_fd {
	my ($fd) = @_;

	my $buf = rpc_recv_packed($fd // *STDIN);
	if (!defined $buf) {
		return;
	}
	return rpc_decode($buf);
}

1;
