package Cluenet::LDAP;
use warnings;
no warnings qw(experimental);
use strict;
use feature qw(state switch);
use base "Exporter";

use Authen::SASL;
use Carp;
use Cluenet;
use Cluenet::Common;
use Data::Dumper;
use Net::LDAP;
use Net::LDAP::Extension::WhoAmI;
use Net::LDAP::Util	qw(ldap_explode_dn);
use Socket::GetAddrInfo	qw(:constants getnameinfo);

=head1 Cluenet::LDAP

Functions that use Net::LDAP.

=cut

our @EXPORT = qw(
	user_to_dn
	user_from_dn
	host_to_dn
	host_from_dn
	hostacl_to_dn
	parse_changelist
	parse_hostservice_safe
);

=head2 user_to_dn($user) -> $dn

Convert a Cluenet username to LDAP DN.

=cut

sub user_to_dn {
	my $user = shift;

	return "uid=${user},ou=people,dc=cluenet,dc=org";
}

=head2 host_to_dn($host) -> $dn

Convert a Cluenet hostname to LDAP DN.

=cut

sub host_to_dn {
	my $host = host_to_fqdn(shift);

	return "cn=${host},ou=servers,dc=cluenet,dc=org";
}

=head2 hostacl_to_dn($host, $service) -> $dn

Convert a Cluenet hostname and service name to Crispy-nssov LDAP DN.

=cut

sub hostacl_to_dn {
	my $host = shift;
	my $service = shift;

	return "cn=${service},cn=svcAccess,".host_to_dn($host);
}

=head2 from_dn($entry_dn, $branch_dn, $value_only=0) -> ($rdn_name, $rdn_value)

Find the next rightmost RDN after given base

=cut

sub from_dn {
	my ($entry_dn, $base_dn, $value_only) = @_;

	my %opts = (reverse => 1, casefold => "lower");

	my @entry = @{ldap_explode_dn($entry_dn, %opts)};
	my @base = @{ldap_explode_dn($base_dn, %opts)};

	for my $rdn (@base) {
		my @erdn = %{shift @entry};
		my @brdn = %$rdn;

		return if !(@erdn ~~ @brdn);
	}

	my @final = %{shift @entry};
	return $value_only ? $final[1] : @final;
}

=head2 user_from_dn($dn) -> $user

Convert a LDAP DN to a Cluenet username.

=cut

sub user_from_dn {
	my $dn = shift;

	return ($dn =~ /=/)
		? from_dn($dn, "ou=people,dc=cluenet,dc=org", 1)
		: $dn;
}

=head2 host_from_dn($dn) -> $host

Convert a LDAP DN to a Cluenet server name (FQDN).

=cut

sub host_from_dn {
	my $dn = shift;

	return ($dn =~ /=/)
		? from_dn($dn, "ou=servers,dc=cluenet,dc=org", 1)
		: $dn;
}

=head2 parse_hostservice($str) -> ($host, $service)

Split a "host/service" (or "host/service/rest") string into $host and $service
(and? $rest), then convert $host into a FQDN.

=cut

sub parse_hostservice_safe {
	my $str = shift;

	my ($host, $service, $rest) = split(m!/!, $str, 3);
	unless (length($host) + length($service)) {
		croak "Syntax error: empty host or service in '$str'";
	}

	return host_to_fqdn($host), $service, $rest;
}

=head2 parse_changelist(\@args, %options) -> \%changes

Parse a list of attribute assignments into LDAP Modify operation parameters.

Arguments:

    attr=value
    attr+=value
    attr-=value
    -=attr

Options:

    translate => sub ($attr, $value) -> ($attr, $value)

=cut

sub parse_changelist {
	my ($args, %opts) = @_;
	my %changes;
	my %attrs;

	for (@$args) {
		/^(?<attr>\w+)(?<op>=|\+=|-=)(?<value>.*)$ | ^(?<op>-=)(?<attr>\w+)$/x
			or do { warn "Error: Invalid operation: $_\n"; return undef; };
		my ($attr, $op, $value) = ($+{attr}, $+{op}, $+{value});

		if ($opts{translate}) {
			($attr, $value) = $opts{translate}->($attr, $value);
		}

		given ($op) {
			when ("=") {
				push @{$changes{replace}{$attr}}, $value;
				$attrs{$attr}{replace}++;
			}
			when ("+=") {
				push @{$changes{add}{$attr}}, $value;
				$attrs{$attr}{add}++;
			}
			when ("-=") {
				if (defined $value) {
					push @{$changes{delete}{$attr}}, $value;
					$attrs{$attr}{delete}++;
				} else {
					$changes{delete}{$attr} = [];
					$attrs{$attr}{delattr}++;
				}
			}
			default {
				warn "Error: Unsupported operation: '$op' for '$attr'\n";
				return undef;
			}
		}
	}
	for my $attr (keys %attrs) {
		my $n = $attrs{$attr};
		if (($n->{add} || $n->{replace}) && $n->{delattr}) {
			warn "Error: When deleting an attribute with '-attr', assignment operators '=' and\n";
			warn "  '-=' will be ignored -- the attribute will be deleted anyway.\n";
			return undef;
		}
		if (($n->{add} || $n->{delete}) && $n->{replace}) {
			warn "Error: It does not make sense to combine '+=' or '-=' operators with '=' for\n";
			warn "  the same attribute, as \"replace\" will take priority over the other two.\n";
			return undef;
		}
	}
	return \%changes;
}

=head2 __ldap_connect_auth(), __ldap_connect_anon() -> $ldaph

Establish an LDAP connection (GSSAPI-authenticated or anonymous).

=cut

sub __ldap_connect_auth {
	my $ldaph = Net::LDAP->new(Cluenet::LDAP_HOST) or croak "$!";

	my $peername = $ldaph->{net_ldap_socket}->peername;
	my ($err, $host) = getnameinfo($peername);
	if ($err) {
		warn "Could not resolve canonical name of LDAP server: $err\n ";
		$host = $ldaph->{net_ldap_host};
	}

	my $sasl = Authen::SASL->new(mech => "GSSAPI");
	my $saslclient = $sasl->client_new("ldap", $host);

	my $msg = $ldaph->bind(sasl => $saslclient);
	if ($msg->code) {
		die "Error: ".$msg->error;
	}

	return $ldaph;
}

sub __ldap_connect_anon {
	my $ldaph = Net::LDAP->new(Cluenet::LDAP_HOST) or croak "$!";

	my $msg = $ldaph->bind();
	if ($msg->code) {
		die "Error: ".$msg->error;
	}

	return $ldaph;
}

=head2 ldap_connect_auth(), ldap_connect_anon() -> $ldaph

Return a singleton handle to the LDAP connection.

=cut

sub ldap_connect_auth {
	our $LDAP_CONN_AUTH;

	return $LDAP_CONN_AUTH //= __ldap_connect_auth;
}

sub ldap_connect_anon {
	our ($LDAP_CONN_AUTH, $LDAP_CONN_ANON);

	return $LDAP_CONN_ANON //= ($LDAP_CONN_AUTH // __ldap_connect_anon);
}

=head2 ldap_format_error($msg, $dn?) -> $text

Format an error message from given LDAP message and optional associated DN.

=cut

sub ldap_format_error {
	my ($msg, $dn) = @_;
	my $text = "LDAP error: ".$msg->error."\n";
	if ($ENV{DEBUG}) {
		$text .= "\tcode: ".$msg->error_name."\n";
	}
	if ($dn) {
		$text .= "\tfailed: $dn\n";
	}
	if ($msg->dn) {
		$text .= "\tmatched: ".$msg->dn."\n";
	}
	return $text;
}

1;
