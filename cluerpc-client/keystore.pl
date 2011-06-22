use feature "say";
use feature "switch";

"keystore" => {
	usage =>
	"keystore {ls|get|put|rm} [name]",

	description =>
	"access the key store",

	requires =>
	["keystore"],

	command =>
	sub {
		my $cmd = shift(@ARGV);
		given ($cmd // "ls") {
			when ("ls") {
				check $r = authenticate;
				check $r = request(cmd => "keystore", action => "list");
				for my $e (@{$r->{items}}) {
					say $e->{name};
				}
			}
			when ("get") {
				my $name = shift(@ARGV);
				check $r = authenticate;
				check $r = request(cmd => "keystore",
							action => "get", name => $name);
				print $r->{data};
			}
			when ("put") {
				my $name = shift(@ARGV);
				my ($buf, $len, $clen);
				while ($clen = STDIN->read($buf, 16384, $len)) {
					if (defined $clen) {
						$len += $clen;
					} else {
						die "$!\n";
					}
				}

				check $r = authenticate;
				check $r = request(cmd => "keystore",
							action => "put", name => $name, data => $buf);
			}
			when ("rm") {
				check $r = authenticate;
				for (@ARGV) {
					check $r => request(cmd => "keystore",
							action => "delete", name => $_);
				}
			}
			default {
				die "Invalid subcommand '$cmd'\n";
			}
		}
	},
};