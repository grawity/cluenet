#!perl
"keystore" => sub {
	my ($state, $req) = @_;

	unless ($state->{authed}) {
		return {failure,
			msg => "access denied"};
	}

	return $state->spawn_helper("rd-keystore", $req);
};
