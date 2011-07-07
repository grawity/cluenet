#!perl
package Cluenet::Rpc::Server;
use warnings;
use strict;
use feature "say";
use base "Exporter";
use base "Cluenet::Rpc";
use Cluenet::Rpc;
use File::Spec;
use IPC::Open2;
use POSIX qw(:sys_wait_h);

our @EXPORT = qw(
	failure
	success
	rpc_helper_main
	);

sub new {
	my $self = {
		infd	=> \*STDIN,
		outfd	=> \*STDOUT,
		eof	=> 0,

		authed	=> 0,
		user	=> "anonymous",
		authzid	=> "anonymous",
	};
	binmode $self->{infd}, ":raw";
	binmode $self->{outfd}, ":raw";
	bless $self, shift;
}

sub spawn_helper {
	my ($self, $name, $req) = @_;
	my (@cmd, $data, $pid, $infd, $outfd, $reply);

	push @cmd, File::Spec->catfile($self->{rpchelperdir} // ".", $name);
	push @cmd, "--for", $self->{user};

	$req //= {};

	$data = {user => $self->{user},
		authuser => $self->{authuser},
		request => $req};

	if ($pid = open2($infd, $outfd, @cmd)) {
		$outfd->print(rpc_encode($data), "\n");
		$outfd->close;
		$reply = rpc_decode($infd->getline);
		waitpid($pid, WNOHANG);
	} else {
		$reply = {failure, msg => "internal error"};
	}
	return $reply;
}

sub rpc_helper_main(&) {
	my ($sub) = @_;

	my ($data, @args, $reply);

	$data = rpc_decode(<STDIN>);
	push @args, $data->{request};
	push @args, $data->{user} // $data->{authuser};
	push @args, $data->{authuser};

	$reply = eval {$sub->(@args)};
	if ($@) {
		chomp $@;
		$reply = {failure, msg => "internal error: $@"};
	} else {
		$reply //= {failure, msg => "internal error"};
	}
	say rpc_encode($reply);
}

1;
