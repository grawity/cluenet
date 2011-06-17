#!perl
package Cluenet::Rpc::Reply;
use warnings;
use strict;

sub new {
	my ($class, $self) = @_;
	bless $self, $class;
}

sub success { (shift)->{status} > 0; }
