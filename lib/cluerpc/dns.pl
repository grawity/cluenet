use feature "say";
use feature "switch";

"dns" => {
	usage =>
	"dns [add|delete|delsubdomain]",

	requires =>
	["dns"],

	command =>
	sub {
		use Getopt::Long qw(:config bundling no_ignore_case);

		my $zone = "cluenet.org";
		GetOptions(
			'z|zone=s'	=> \$zone,
		) or die "$@";

		my $action = shift(@ARGV);
		given ($action) {
			when (undef) {
				my @delete;
				my @add;

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
				}
				if (@add) {
					check $r = request(cmd => "dns",
								action => "add",
								zone => $zone,
								records => \@add);
				}
			}

			when ("add") {
				my @records;
				while (my $line = <STDIN>) {
					chomp($line);
					my ($fqdn, $ttl, $type, $data) = split(/\s+/, $line, 4);
					push @records, {
						fqdn	=> $fqdn,
						ttl	=> $ttl,
						type	=> $type,
						data	=> $data};
				}
				
				check $r = authenticate;
				check $r = request(cmd => "dns",
							action => $action,
							zone => $zone,
							records => \@records);
			}

			when ("delete") {
				my @records;
				while (my $line = <STDIN>) {
					chomp($line);
					my ($fqdn, $type, $data) = split(/\s+/, $line, 3);
					push @records, {
						fqdn	=> $fqdn,
						type	=> $type,
						data	=> $data};
				}
				
				check $r = authenticate;
				check $r = request(cmd => "dns",
							action => $action,
							zone => $zone,
							records => \@records);
			}

			when ("delsubdomain") {
				my @domains;
				while (my $line = <STDIN>) {
					chomp($line);
					push @domains, $line;
				}
				
				check $r = authenticate;
				check $r = request(cmd => "dns",
							action => $action,
							domains => \@domains);
			}

			default {
				die "Invalid action '$action'\n";
			}
		}
	},
};
