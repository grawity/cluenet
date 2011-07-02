#!perl
"grant_mysql" => sub {
	my ($state, $req) = @_;

	unless ($state->{authed}) {
		return {failure,
			msg => "access denied"};
	}

	$req->{user} = $state->{user};
	$req->{ifexists} = 0;
	return $state->spawn_helper("rd-mysql", $req);
};
