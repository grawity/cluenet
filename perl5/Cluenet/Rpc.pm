#!perl
package Cluenet::Rpc;
use warnings;
use strict;
use base "Exporter";
use feature "say";

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

sub failure { status => 0 }
sub success { status => 1 }

sub rpc_encode { encode_json(shift // {}); }
sub rpc_decode { decode_json(shift || '{}'); }

sub b64_encode { MIME::Base64::encode_base64(shift // "", "") }
sub b64_decode { MIME::Base64::decode_base64(shift // "") }

=protocol

Basic structure:

	char magic[4]		= "!rpc"
	char length[4]		= data length in hexadecimal
	char data[length]	= RPC data

If negotiated during authentication, data is encrypted using sasl_encode().

Data is a JSON-encoded hash.

	* Requests always have "cmd" set to the command name.
	* Replies always have "status" set to 1 (success) or 0 (failure).
	* Failure replies normally have "msg" set to a short description.

=cut

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
	unless ($fd->read($buf, 8)) {
		return {failure, msg => "connection closed"};
	}
	# check magic number to avoid parsing Perl errors
	unless (substr($buf, 0, 4) eq "!rpc") {
		return {failure, msg => "invalid data",
			data => $buf.$fd->getline};
	}
	# read data
	$len = hex(substr($buf, 4));
	unless ($fd->read($buf, $len) == $len) {
		return {failure, msg => "connection closed"};
	}
	return $buf;
}

sub rpc_send {
	my $self = shift;
	my $data = rpc_encode(shift);
	$self->{debug} and warn "SEND: $data\n";
	if ($self->{seal}) {
		$data = $self->{sasl}->encode($data);
	}
	rpc_send_packed($self->{outfd}, $data);
}

sub rpc_recv {
	my $self = shift;
	my $data = rpc_recv_packed($self->{infd});
	if ($self->{seal}) {
		$data = $self->{sasl}->decode($data);
	}
	$self->{debug} and warn "RECV: $data\n";
	return rpc_decode($data);
}

1;
