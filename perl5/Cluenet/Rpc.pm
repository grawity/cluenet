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

	magic[4]	= "!rpc"
	length[4]	= data length in hexadecimal
	data[length]	= RPC data

If negotiated during authentication, data is encrypted using sasl_encode().

Data is a JSON-encoded hash.

	* Requests always have "cmd" set to the command name.
	* Replies always have "status" set to 1 (success) or 0 (failure).
	* Failure replies normally have "msg" set to a short description.

=cut

sub rpc_send {
	my $state = shift;
	my $data = rpc_encode(shift);
	$state->{debug} and warn "SEND: $data\n";
	if ($state->{seal}) {
		$data = $state->{sasl}->encode($data);
	}
	$state->{outfd}->printf("!rpc%04x", length($data));
	$state->{outfd}->write($data, length($data));
	$state->{outfd}->flush;
	return;
}

sub rpc_recv {
	my $state = shift;
	my ($len, $buf);
	unless ($state->{infd}->read($buf, 8)) {
		return {failure, msg => "connection closed"};
	}
	unless (substr($buf, 0, 4) eq "!rpc") {
		# check for magic number to avoid trying to parse Perl errors
		$state->{debug} and warn "DATA? ".$buf.$state->{infd}->getline."\n";
		return {failure, msg => "invalid data"};
	}
	$len = hex(substr($buf, 4));
	unless ($state->{infd}->read($buf, $len) == $len) {
		return {failure, msg => "connection closed"};
	}
	if ($state->{seal}) {
		$buf = $state->{sasl}->decode($buf);
	}
	$state->{debug} and warn "RECV: $buf\n";
	return rpc_decode($buf);
}

1;
