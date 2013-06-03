#!perl
package Cluenet::Rpc::Server;
use common::sense;
use base "Exporter";
use Carp;
use Cluenet::Rpc::Connection;
use IPC::Open2;
use POSIX qw(:sys_wait_h);

our @EXPORT = qw(
	failure
	success
	rpc_helper_main
);

# macros for use in RPC return codes

sub failure	{ success => 0 }
sub success	{ success => 1 }

# server class

sub new {
	my ($class) = @_;
	my $self = {
		connection	=> undef,
		eof		=> 0,
		handler		=> undef,
		sasl_service	=> "host",
	};
	bless $self, $class;
}

sub set_handler {
	my ($self, $sub) = @_;
	$self->{handler} = $sub;
}

sub loop {
	my ($self) = @_;
	if (!$self->{handler}) {
		croak "Starting main loop without a request handler";
	}

	while (my $in = $self->{connection}->recv()) {
		my $out = $self->{handler}->($self, $in);
		$self->{connection}->send($out);

		last if $self->{eof};
	}
}

sub stop_loop {
	my ($self) = @_;
	$self->{eof} = 1;
}

sub spawn_helper {
	my ($self, $name, @args) = @_;

	my @command = ("/cluenet/lib/cluerpcd/$name",
			"-z", $self->{user});

	unshift @args, 
		{logged_in => $self->{logged_in},
		user => $self->{user},
		authn => $self->{auth_user}};

	my ($pid, $rfd, $wfd, $reply);

	if ($pid = open2($rfd, $wfd, @command)) {
		my $child = Cluenet::Rpc::Connection->new($rfd, $wfd);
		$child->send(\@args);
		$wfd->close;
		$reply = $child->recv();
		waitpid($pid, WNOHANG);
	} else {
		$reply = {failure,
			error => "internal error: failed to execute '$command[0]'"};
	}
	return $reply;
}

sub rpc_helper_main(&) {
	my ($func) = @_;

	my $parent = Cluenet::Rpc::Connection->new(\*STDIN, \*STDOUT);
	my $args = $parent->recv();
	my @args;

	given (ref $args) {
		when ('ARRAY') {
			@args = @$args;
		}
		when ('HASH') {
			@args = %$args;
		}
		default {
			return {failure,
				error => "rpc: invalid args type"};
		}
	}

	my $reply = eval { $func->(@args) };

	if ($@) {
		chomp $@;
		$reply = {failure,
			error => "internal error: $@"};
	} else {
		$reply //= {failure,
			error => "internal error: null reply from helper"};
	}
	$parent->send($reply);
}

1;

