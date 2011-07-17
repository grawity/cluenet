use feature "say";
use feature "switch";

"keystore" => {
	usage =>
	"keystore {ls|get|put|rename|delete} [name]",

	description =>
	"access the key store",

	requires =>
	["keystore"],

	command =>
	sub {
		my $action = shift(@ARGV);
		given ($action // "ls") {
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
			when (["rename", "mv"]) {
				check $r = authenticate;
				my ($name, $to) = @ARGV;
				check $r = request(cmd => "keystore", action => "rename",
						name => $name, to => $to);
			}
			when (["delete", "rm"]) {
				check $r = authenticate;
				for (@ARGV) {
					check $r => request(cmd => "keystore",
							action => "delete", name => $_);
				}
			}
			default {
				die "Invalid action '$action'\n";
			}
		}
	},
};
