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
	sasl_encode
	sasl_decode
	failure
	success
	rpc_encode
	rpc_decode
	);

sub failure { status => 0 }
sub success { status => 1 }

sub rpc_encode { encode_json(shift // {}); }
sub rpc_decode { decode_json(shift || '{}'); }

sub rpc_send {
	my $state = shift;
	my $data = rpc_encode(shift);
	$ENV{DEBUG} and warn "SEND: $data\n";
	if ($state->{seal}) {
		$data = $state->{sasl}->encode($data);
	}
	$state->{outfd}->write(pack("N", length($data)), 4);
	$state->{outfd}->write($data, length($data));
	$state->{outfd}->flush;
	return;
}

sub rpc_recv {
	my $state = shift;
	my ($len, $buf);
	use MIME::Base64;
	unless ($state->{infd}->read($buf, 4)) {
		return {failure, msg => "connection closed"};
	}
	$len = unpack("N", $buf);
	unless ($state->{infd}->read($buf, $len) == $len) {
		return {failure, msg => "connection closed"};
	}
	if ($state->{seal}) {
		$buf = $state->{sasl}->decode($buf);
	}
	$ENV{DEBUG} and warn "RECV: $buf\n";
	return rpc_decode($buf);
}

sub sasl_encode { encode_base64(shift // "", "") }
sub sasl_decode { decode_base64(shift // "") }

##


1;
