use feature "say";

"reset-password" => {
	usage =>
	"reset-password SERVICE",

	description =>
	"reset password for given service",

	requires =>
	["reset_password"],

	command =>
	sub {
		### TODO ### get services from remote
		my @services = qw(mysql samba);

		my $service = shift(@ARGV);
		if (defined $service) {
			confirm "Reset $service password for '\033[1m${user}\033[m'?";

			check $r = authenticate;
			check $r = request(cmd => "reset_password", service => $service);
			say "Password for '$r->{account}{username}' has been reset.";
			say "";
			say "New password:\t".$r->{account}{password};
			say "";
			if ($r->{msg}) {
				say $r->{msg};
				say "";
			}
		} else {
			check $r = authenticate;
			check $r = request(cmd => "reset_password", service => "");
			say "Supported services: ", join(", ", @{$r->{services}});
		}
	},
};
