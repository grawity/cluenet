#!perl
sub {
	my ($self, $req) = @_;

	unless ($self->{authed}) {
		return {failure,
			msg => "access denied"};
	}
	unless ($req->{service}) {
		return {failure,
			msg => "missing parameter"};
	}

	$req->{user} = $self->{user};
	$req->{action} = $req->{revoke} ? "revoke" : "grant";
	return $self->spawn_helper("rd-access", $req);
};
