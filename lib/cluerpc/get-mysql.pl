use feature "say";

"get-mysql" => {
	usage =>
	"get-mysql",

	description =>
	"create a MySQL account",

	requires =>
	["grant_mysql"],

	command =>
	sub {
		confirm "Create MySQL account '\033[1m${user}\033[m'?";

		check $r = authenticate;
		check $r = request(cmd => "grant_mysql");

		say "MySQL account updated.";
		say "";
		say "Username:\t".$r->{account}{username};
		say "Password:\t".$r->{account}{password};
		say "Databases:\t".$r->{account}{db_glob};
		say "";
		if ($r->{admin_url}) {
			say "You can change the password and create databases at:";
			say $r->{admin_url};
			say "";
		}
	},
};
