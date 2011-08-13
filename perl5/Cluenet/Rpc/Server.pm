#!perl
package Cluenet::Rpc::Server;
use parent 'Cluenet::Rpc';
use parent 'Exporter';
use common::sense;
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
	my ($class) = @_;
	my $self = {
		rfd	=> \*STDIN,
		wfd	=> \*STDOUT,
		eof	=> 0,

		authed		=> 0,
		user		=> "anonymous",
		authzid		=> "anonymous",

		seal		=> 0,
		seal_want	=> 0,
		seal_next	=> 0,
	};
	binmode $self->{rfd}, ":raw";
	binmode $self->{wfd}, ":raw";
	bless $self, $class;
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
	my ($pid, $rfd, $wfd, $reply);

	if ($pid = open2($rfd, $wfd, @$cmd)) {
		my $ext = Cluenet::Rpc->new($rfd, $wfd);
		$ext->rpc_send($data);
		$wfd->close;
		$reply = $ext->rpc_recv;
		waitpid($pid, WNOHANG);
	} else {
		$reply = {failure,
			msg => "internal error: spawn_ext failed to execute '${cmd}[0]'"};
	}
	return $reply;
}

sub rpc_helper_main(&) {
	my ($sub) = @_;

	my ($data, @args, $reply);
	my $parent = Cluenet::Rpc->new;
	$data = $parent->rpc_recv;
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
			msg => "internal error: rpc_helper_main failed"};
	}
	$parent->rpc_send($reply);
}

sub rpc_ext_main(&) {
	my ($sub) = @_;

	my ($data, $reply);
	my $parent = Cluenet::Rpc->new;
	$data = $parent->rpc_recv;

	$reply = eval {$sub->($data)};
	if ($@) {
		chomp $@;
		$reply = {failure,
			msg => "internal error: $@"};
	} else {
		$reply //= {failure,
			msg => "internal error: rpc_ext_main failed"};
	}
	$parent->rpc_send($reply);
}

1;
