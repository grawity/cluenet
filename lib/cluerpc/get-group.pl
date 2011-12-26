use feature "say";

"get-group" => {
	usage =>
	"[-]GROUP",

	requires =>
	["grant_group"],

	command =>
	sub {
		my $group = shift(@ARGV);
		my $do_revoke = ($group =~ s/^-//);

		$rpc->authenticate;
		my $reply = $rpc->grant_group(group => $group,
						revoke => $do_revoke);
	
		if ($reply->{success}) {
			say "Success.";
		}
	},
};
