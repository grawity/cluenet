use feature "say";

"get-mysql" => {
	usage =>
	"",

	description =>
	"create a MySQL account",

	requires =>
	["grant_mysql"],

	command =>
	sub {
		confirm "Create MySQL account '\033[1m$user\033[m'?";

		$rpc->authenticate;
		my $reply = $rpc->grant_mysql();

		say "MySQL account updated.";
		say "";
		say "Username:\t".$reply->{account}{username};
		say "Password:\t".$reply->{account}{password};
		say "Databases:\t".$reply->{account}{db_glob};
		say "";
		if ($reply->{admin_url}) {
			say "You can change the password and create databases at:";
			say $reply->{admin_url};
			say "";
		}
	},
};
