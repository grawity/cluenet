package Cluenet::LDAP;
use warnings;
no if $] >= 5.018,
	warnings => qw(experimental::smartmatch);
use strict;
use feature qw(state);
use base "Exporter";

use Authen::SASL;
use Carp;
use Cluenet;
use Cluenet::Common;
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
	ldap_connect
);

=head2 user_to_dn($user) -> $dn

Convert a Cluenet username to its LDAP DN. (Returns garbage if $user is already a
DN or something else.)

=cut

sub user_to_dn {
	my $user = shift;

	return "uid=${user},ou=people,dc=cluenet,dc=org";
}

=head2 user_to_dn_maybe($user) -> $dn

Convert a Cluenet username to its LDAP DN, if it isn't already.

=cut

sub user_to_dn_maybe {
	my $user = shift;

	return $user =~ /^\w+=/ ? $user : user_to_dn($user);
}

=head2 host_to_dn($host) -> $dn

Convert a Cluenet hostname to its LDAP DN.

=cut

sub host_to_dn {
	my $host = host_to_fqdn(shift);

	return "cn=${host},ou=servers,dc=cluenet,dc=org";
}

=head2 hostacl_to_dn($host, $service) -> $dn

Convert a Cluenet hostname and service name to their Crispy-nssov LDAP DN.

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
    -attr

Options:

    translate => sub ($attr, $value) -> ($attr, $value)

=cut

sub parse_changelist {
	my ($args, %opts) = @_;
	my %changes;
	my %attrs;

	for (@$args) {
		/^(?<attr>\w+)(?<op>=|\+=|-=)(?<value>.*)$ | ^(?<op>-)(?<attr>\w+)$/x
			or do { warn "Error: Invalid operation: $_\n"; return undef; };
		my ($attr, $op, $value) = ($+{attr}, $+{op}, $+{value});

		if ($opts{translate}) {
			($attr, $value) = $opts{translate}->($attr, $value);
		}

		for ($op) {
			if ($_ eq "=") {
				push @{$changes{replace}{$attr}}, $value;
				$attrs{$attr}{replace}++;
			}
			elsif ($_ eq "+=") {
				push @{$changes{add}{$attr}}, $value;
				$attrs{$attr}{add}++;
			}
			elsif ($_ eq "-=") {
				push @{$changes{delete}{$attr}}, $value;
				$attrs{$attr}{delete}++;
			}
			elsif ($_ eq "-") {
				$changes{delete}{$attr} = [];
				$attrs{$attr}{delattr}++;
			}
			else {
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

=head2 _ldap_connect(%opt) -> $ldaph

Establish an LDAP connection (GSSAPI-authenticated or anonymous).

Options:
	bool auth => 0

=cut

sub _ldap_connect {
	my %opt = @_;
	my $res;

	put_status("Connecting to LDAP server...");

	my $ldaph = Net::LDAP->new($Cluenet::LDAP_HOST) or croak "$!";

	if ($opt{auth}) {
		my $peername = $ldaph->{net_ldap_socket}->peername;

		my ($err, $host) = getnameinfo($peername);
		if ($err) {
			warn "Could not resolve canonical name of LDAP server: $err\n ";
			$host = $ldaph->{net_ldap_host};
		}

		my $sasl = Authen::SASL->new(mech => "GSSAPI");
		my $saslclient = $sasl->client_new("ldap", $host);

		$res = $ldaph->bind(sasl => $saslclient);
		if ($res->code) { die "Error: ".$res->error; }
	} else {
		$res = $ldaph->bind();
		if ($res->code) { die "Error: ".$res->error; }
	}

	put_status();

	return $ldaph;
}

=head2 ldap_connect(%opt) -> $ldaph

Return a singleton handle to the LDAP connection.

=cut

sub ldap_connect {
	my %opt = @_;
	state $conn_auth;
	state $conn_anon;

	if ($conn_auth) {
		return $conn_auth;
	} elsif ($opt{auth}) {
		$conn_auth = _ldap_connect(%opt);
		if ($conn_anon) {
			$conn_anon->unbind;
		}
		$conn_anon = $conn_auth;
		return $conn_auth;
	} elsif ($conn_anon) {
		return $conn_anon;
	} else {
		$conn_anon = _ldap_connect(%opt);
		return $conn_anon;
	}
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
