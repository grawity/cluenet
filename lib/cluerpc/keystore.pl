use feature "say";
use feature "switch";

"keystore" => {
	usage =>
	"{ls|get|put|rename|delete} [name]",

	description =>
	"access the key store",

	requires =>
	["keystore"],

	command =>
	sub {
		my $action = shift(@ARGV);
		$rpc->authenticate;
		given ($action // "list") {
			when (["list", "ls"]) {
				my $reply = $rpc->keystore(action => "list");
				for my $item (@{$reply->{items}}) {
					say $item->{name};
				}
			}
			when ("get") {
				for (@ARGV) {
					my $reply = $rpc->keystore(action => "get", name => $_);
					print $reply->{data};
				}
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
				$rpc->keystore(action => "put", name => $name, data => $buf);
			}
			when (["rename", "mv"]) {
				my ($name, $to) = @ARGV;
				$rpc->keystore(action => "rename", name => $name, to => $to);
			}
			when (["delete", "rm"]) {
				for (@ARGV) {
					$rpc->keystore(action => "delete", name => $_);
				}
			}
			default {
				die "Invalid action '$action'\n";
			}
		}
	},
};
