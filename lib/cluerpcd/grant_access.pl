#!perl
"grant_access" => sub {
	my ($self, $req) = @_;

	unless ($self->{authed}) {
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

	$req->{user} = $self->{user};
	$req->{action} = $req->{revoke} ? "revoke" : "grant";
	return $self->spawn_helper("rd-access", $req);
};
