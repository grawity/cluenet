use feature "say";
use feature "switch";

"dns" => {
	usage =>
	"dns [add|delete|delsubdomain]",

	requires =>
	["dns"],

	command =>
	sub {
		my $action = shift(@ARGV);
		my $zone = shift(@ARGV);
		given ($action) {
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
