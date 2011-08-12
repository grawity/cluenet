#!perl
use feature "switch";

"reset_password" => sub {
	my ($self, $req) = @_;

	my %services = (
		mysql => sub {
			my $data = {user => $self->{user}, ifexists => 1};
			return $self->spawn_helper("rd-mysql", $data);
		},
		samba => sub {
			return $self->spawn_helper("rd-smbpasswd");
		},
	);

	unless ($self->{authed}) {
		return {failure,
			msg => "access denied"};
	}

	my $svc = $req->{service};

	if (!defined $svc) {
		return {failure,
			msg => "missing parameter"};
	}
	elsif ($svc eq "") {
		return {success,
			services => [keys %services]};
	}
	elsif (exists $services{$svc}) {
		return $services{$svc}->();
	}
	else {
		return {failure,
			msg => "unknown service: '$svc'"};
	}
};
