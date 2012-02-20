#!perl
package Cluenet::Rpc;
use base "Exporter";
use common::sense;
use MIME::Base64;

our @EXPORT = qw(
	b64_encode
	b64_decode
);

our $DEBUG = $ENV{DEBUG};

# shortcut methods for encoding Base64

sub b64_encode	{ MIME::Base64::encode_base64(shift // "", "") }
sub b64_decode	{ MIME::Base64::decode_base64(shift // "") }

1;
