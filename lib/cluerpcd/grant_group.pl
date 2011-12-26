#!perl
use feature "switch";

sub {
	my ($self, $req) = @_;

	unless ($self->{authed}) {
		return {failure,
			msg => "access denied"};
	}
	return $self->spawn_helper("rd-group", $req);
};
