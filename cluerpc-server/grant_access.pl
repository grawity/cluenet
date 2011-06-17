#!perl
"grant_access" => sub {
	my ($state, $req) = @_;

	unless ($state->{authed}) {
		return {failure,
			msg => "access denied"};
	}
	unless ($req->{server} and $req->{service}) {
		return {failure,
			msg => "missing parameter"};
	}
	unless ($req->{server} eq getfqdn()) {
		return {failure,
			msg => "wrong server"};
	}

	$req->{action} = $req->{revoke} ? "revoke" : "grant";
	$req->{user} = $state->{authzid};
	return $state->spawn_helper("rd-access", $req);
};
