use feature "say";

"reset-password" => {
	usage =>
	"SERVICE",

	description =>
	"reset password for given service",

	requires =>
	["reset_password"],

	command =>
	sub {
		$rpc->authenticate;
		my $reply = $rpc->reset_password(service => "");
		my @services = @{$reply->{services}};

		my $service = shift(@ARGV);
		if (defined $service) {
			confirm "Reset $service password for '\033[1m$user\033[m'?";
			$reply = $rpc->reset_password(service => $service);
			if (exists $reply->{account}{password}) {
				say "Password for '$reply->{account}{username}' has been reset.";
				say "";
				say "New password:\t".$reply->{account}{password};
				say "";
			}
			if (exists $reply->{msg}) {
				say $reply->{msg};
				say "";
			}
		} else {
			warn "Error: service not specified\n";
			say "Services: ", join(", ", @services);
		}
	},
};
