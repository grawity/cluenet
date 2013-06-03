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

1;
