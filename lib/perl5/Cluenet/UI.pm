package Cluenet::UI;
use warnings;
use strict;

sub _is_interactive {
	-t 2 && !defined $ENV{CN_NO_STATUS};
}

sub _in_nush {
	defined $ENV{CN_NUSH};
}

sub _print_status {
	my ($msg) = @_;

	if (_is_interactive) {
		my @m = "\r\033[K";
		if (defined $msg) {
			push @m, "\033[38;5;10m", $msg, "\033[m";
		}
		print STDERR @m;
		$|++;
	}
}

sub cred_check {
	system("klist", "-5", "-s") == 0;
}

sub cred_ensure {
	if (!cred_check() && _in_nush) {
		die "\e[1;31merror:\e[m not logged in\n";
	}

	if (!cred_check() && _is_interactive) {
		system("kinit", "-5");
	}

	if (!cred_check()) {
		die "Please run 'kinit' to log into your Cluenet account.\n";
	}
}

$Cluenet::UI_CB{status} = \&_print_status;

1;
