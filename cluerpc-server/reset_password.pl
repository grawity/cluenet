#!perl
use feature "switch";

"reset_password" => sub {
	my ($state, $req) = @_;

	my @services = qw(mysql samba);

	unless ($state->{authed}) {
		return {failure,
			msg => "access denied"};
	}

	unless (defined $req->{service}) {
		return {failure,
			msg => "missing parameter"};
	}

	given ($req->{service}) {
		when ("mysql") {
			my $data = {user => $state->{authzid}, ifexists => 1};
			return $state->spawn_helper("rd-mysql", $data);
		}
		when ("samba") {
			return $state->spawn_helper("rd-smbpasswd");
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
