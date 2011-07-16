#!perl
use feature "switch";

"reset_password" => sub {
	my ($self, $req) = @_;

	unless ($self->{authed}) {
		return {failure,
			msg => "access denied"};
	}
	unless (defined $req->{service}) {
		return {failure,
			msg => "missing parameter"};
	}

	my @services = qw(mysql samba);

	given ($req->{service}) {
		when ("mysql") {
			my $data = {user => $self->{user}, ifexists => 1};
			return $self->spawn_helper("rd-mysql", $data);
		}
		when ("samba") {
			return $self->spawn_helper("rd-smbpasswd");
		}
		when ("") {
			return {success,
				services => \@services};
		}
		default {
			return {failure,
				msg => "unknown service"};
		}
	}
};
