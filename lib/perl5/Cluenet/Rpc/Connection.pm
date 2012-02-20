#!perl
package Cluenet::Rpc::Connection;
#use common::sense;
use warnings;
use strict;
use Carp;
use IO::Handle;
use JSON;

# low-level class for exchanging data over a pair of FDs

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
	bless $self, $class;
}

sub close {
	my ($self) = @_;
	$self->{wfd}->close;
	$self->{rfd}->close;
}

# send/receive packets of length + binary data

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
	if (!defined $len) {
		croak "RPC: read error: $!";
	}
	unless ($len == 16) {
		warn "RPC: short read ($len bytes out of 16)";
		return undef;
	}
	unless ($buf =~ /^NullRPC:[0-9a-f]{8}$/) {
		chomp($buf .= $self->{rfd}->getline);
		$self->{wfd}->print("Protocol mismatch.\n");
		$self->close;
		croak "RPC: protocol mismatch, received '$buf'";
		return undef;
	}
	$len = hex(substr($buf, 8));
	unless ($self->{rfd}->read($buf, $len) == $len) {
		return undef;
	}
	return $buf;
}

# send/receive Perl/JSON objects

sub serialize {
	return encode_json(shift // {});
}

sub unserialize {
	return decode_json(shift || '{}');
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

1;
