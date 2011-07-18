use feature "say";
use feature "switch";

"dns" => {
	usage =>
	"[add|delete|update|delsubdomain]",

#	description =>
#	"update DNS information",

	help =>
	{
		add =>
		"-f fqdn [-T ttl] -t type -d data",

		delete =>
		"-f fqdn [-t type [-d data]]",

		update =>
		"[< commands]",

		delsubdomain =>
		"fqdn",
	},

	requires =>
	["dns"],

	command =>
	sub {
		use Getopt::Long qw(:config bundling no_ignore_case);

		my $zone = "cluenet.org";
		my $quiet = 0;

		GetOptions(
			'q|quiet!'	=> \$quiet,
			'z|zone=s'	=> \$zone,
		) or die "$@";

		my $action = shift(@ARGV) // "help";

		given ($action) {
			when ("update") {
				my (@add, @delete);

				if (-t 0) {
					say "# add <fqdn> <ttl> <type> <data>";
					say "# delete <fqdn> [<type> [<data>]]";
				}

				while (my $line = <STDIN>) {
					chomp($line);
					if ($line =~ s/^add\s+//) {
						my ($fqdn, $ttl, $type, $data) = split(/\s+/, $line, 4);
						push @add, {
							fqdn	=> $fqdn,
							ttl	=> $ttl,
							type	=> $type,
							data	=> $data};
					}
					elsif ($line =~ s/^del\s+//) {
						my ($fqdn, $type, $data) = split(/\s+/, $line, 3);
						push @records, {
							fqdn	=> $fqdn,
							type	=> $type,
							data	=> $data};
					}
					else {
						die "Syntax error.\n";
					}
				}

				check $r = authenticate;
				if (@add) {
					check $r = request(cmd => "dns",
								action => "validate",
								zone => $zone,
								records => \@add);
				}
				if (@delete) {
					check $r = request(cmd => "dns",
								action => "delete",
								zone => $zone,
								records => \@delete);
					$quiet || say $r->{count}." records deleted.";
				}
				if (@add) {
					check $r = request(cmd => "dns",
								action => "add",
								zone => $zone,
								records => \@add);
					$quiet || say $r->{count}." records added.";
				}
			}

			when ("add") {
				my %rec;
				GetOptions(
					'f|fqdn=s'	=> \$rec{fqdn},
					'T|ttl=i'	=> \$rec{ttl},
					't|type=s'	=> \$rec{type},
					'd|data=s'	=> \$rec{data},
				) or die "$@";

				unless (defined $rec{fqdn} and defined $rec{type} and defined $rec{data}) {
					die "Missing fqdn, type and/or data\n";
				}
				$rec{ttl} //= 10800;
				check $r = authenticate;
				check $r = request(cmd => "dns",
							action => "add",
							zone => $zone,
							records => [\%rec]);

				$quiet || say $r->{count}." records added.";
			}

			when ("delete") {
				my %rec;
				GetOptions(
					'f|fqdn=s'	=> \$rec{fqdn},
					't|type=s'	=> \$rec{type},
					'd|data=s'	=> \$rec{data},
				) or die "$@";

				unless (defined $rec{fqdn}) {
					die "Missing fqdn\n";
				}
				check $r = authenticate;
				check $r = request(cmd => "dns",
							action => "delete",
							zone => $zone,
							records => [\%rec]);

				$quiet || say $r->{count}." records deleted.";
			}

			when ("delsubdomain") {
				my @domains = @ARGV;

				return unless @domains;
				check $r = authenticate;
				check $r = request(cmd => "dns",
							action => $action,
							domains => \@domains);

				$quiet || say $r->{count}." records deleted.";
			}

			default {
				die "Invalid action '$action'\n";
			}
		}
	},
};
