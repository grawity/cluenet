#!perl
name => "keystore",

access => "auth",

func => sub {
	my ($state, $req) = @_;
	use MIME::Base64;

	unless ($state->{authed}) {
		return {failure,
			msg => "access denied"};
	}

	return $state->spawn_helper("rd-keystore", $req);
};
