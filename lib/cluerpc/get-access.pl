use feature "say";
use feature "switch";

"get-access" => {
	usage =>
	"[-]SERVICE",

	description =>
	"request access to a service (samba, ftp)",

	requires =>
	["grant_access"],

	command =>
	sub {
		my $service = shift(@ARGV);
		my $do_revoke = ($service =~ s/^-//);

		$rpc->authenticate;
		my $reply = $rpc->grant_access(service => $service,
						revoke => $do_revoke);

		given ($reply->{action}) {
			when ("grant") {
				say "Access granted to ".join(", ", @{$reply->{services}});
			}
			when ("revoke") {
				say "Access revoked to ".join(", ", @{$reply->{services}});
			}
			when ("request-sent") {
				say "Request forwarded to administrators.";
			}
		}
	},
};
