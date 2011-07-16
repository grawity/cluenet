#!perl
"keystore" => sub {
	my ($self, $req) = @_;

	unless ($self->{authed}) {
		return {failure,
			msg => "access denied"};
	}

	return $self->spawn_helper("rd-keystore", $req);
};
