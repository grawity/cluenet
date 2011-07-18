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
	spawn_ext
	rpc_helper_main
	rpc_ext_main
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

	my @cmd = (File::Spec->catfile($self->{rpchelperdir} // ".", $name),
			"--for",
			$self->{user});

	my $data = {user => $self->{user},
		authuser => $self->{authuser},
		request => $req // {}};

	return spawn_ext(\@cmd, $data);
}

sub spawn_ext {
	my ($cmd, $data) = @_;
	my ($pid, $infd, $outfd, $reply);

	if ($pid = open2($infd, $outfd, @$cmd)) {
		Cluenet::Rpc::rpc_send_fd($data, $outfd);
		$outfd->close;
		$reply = Cluenet::Rpc::rpc_recv_fd($infd);
		waitpid($pid, WNOHANG);
	} else {
		$reply = {failure,
				msg => "internal error",
				err => "spawn_ext failed to execute '${cmd}[0]'"};
	}
	return $reply;
}

sub rpc_helper_main(&) {
	my ($sub) = @_;

	my ($data, @args, $reply);

	$data = Cluenet::Rpc::rpc_recv_fd(*STDIN);
	push @args, $data->{request};
	push @args, $data->{user} // $data->{authuser};
	push @args, $data->{authuser};

	$reply = eval {$sub->(@args)};
	if ($@) {
		chomp $@;
		$reply = {failure,
				msg => "internal error: $@"};
	} else {
		$reply //= {failure,
				msg => "internal error",
				err => "rpc_helper_main failed"};
	}
	Cluenet::Rpc::rpc_send_fd($reply, *STDOUT);
}

sub rpc_ext_main(&) {
	my ($sub) = @_;

	my ($data, $reply);
	$data = Cluenet::Rpc::rpc_recv_fd(*STDIN);

	$reply = eval {$sub->($data)};
	if ($@) {
		chomp $@;
		$reply = {failure,
				msg => "internal error: $@"};
	} else {
		$reply //= {failure,
				msg => "internal error",
				err => "rpc_ext_main failed"};
	}
	Cluenet::Rpc::rpc_send_fd($reply, *STDOUT);
}

1;
