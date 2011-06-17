use feature "say";
use feature "switch";

"access" => {
	usage =>
	"access [-]SERVICE",

	description =>
	"request access to a service (samba, ftp)",

	command =>
	sub {
		my $service = shift(@ARGV);

		my $do_revoke = ($service =~ s/^-//);

		check $r = authenticate("GSSAPI");
		check $r = request(cmd => "grant_access",
					server => getfqdn(),
					service => $service,
					revoke => $do_revoke);

		given ($r->{action}) {
			when ("grant") {
				say "Access granted to ".join(", ", @{$r->{services}});
			}
			when ("revoke") {
				say "Access revoked to ".join(", ", @{$r->{services}});
			}
			when ("request-sent") {
				say "Request forwarded to administrators.";
			}
		}
	},
};
