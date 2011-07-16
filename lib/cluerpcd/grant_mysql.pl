#!perl
"grant_mysql" => sub {
	my ($self, $req) = @_;

	unless ($self->{authed}) {
		return {failure,
			msg => "access denied"};
	}

	$req->{user} = $self->{user};
	$req->{ifexists} = 0;
	return $self->spawn_helper("rd-mysql", $req);
};
