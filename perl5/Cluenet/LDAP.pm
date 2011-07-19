#!perl
package Cluenet::LDAP;
use warnings;
use strict;
use base "Exporter";

use Authen::SASL;
use Carp;
use Cluenet::Common;
use Net::LDAP;
use Net::LDAP::Extension::WhoAmI;
use Net::LDAP::Util qw(ldap_explode_dn);

use constant {
	LDAP_HOST	=> "ldap.cluenet.org",
	LDAP_MASTER	=> "ldap.cluenet.org",
};

our @EXPORT = qw(
	user_dn
	server_dn
	from_dn
	user_from_dn
	server_from_dn
	ldap_connect_auth
	ldap_connect_anon
	ldap_errmsg
	);

my $whoami;

sub user_dn { "uid=".shift().",ou=people,dc=cluenet,dc=org" }

sub server_dn { "cn=".Cluenet::Common::server_fqdn(shift).",ou=servers,dc=cluenet,dc=org" }

# Find the next rightmost RDN after given base
sub from_dn {
	my ($entrydn, $branchdn, $nonames) = @_;
	my %opts = (reverse => 1, casefold => "lower");
	my @entry = @{ldap_explode_dn($entrydn, %opts)};
	my @base = @{ldap_explode_dn($branchdn, %opts)};
	for my $rdn (@base) {
		my @brdn = %$rdn;
		my @erdn = %{shift @entry};
		return if ($erdn[0] ne $brdn[0]) or ($erdn[1] ne $brdn[1]);
	}
	my @final = %{shift @entry};
	return $nonames ? $final[1] : @final;
}

sub user_from_dn {
	from_dn(shift, "ou=people,dc=cluenet,dc=org", 1);
}

sub server_from_dn {
	from_dn(shift, "ou=servers,dc=cluenet,dc=org", 1);
}

# Establish LDAP connection, authenticated or anonymous
sub connect_auth {
	my $ldap = Net::LDAP->new(LDAP_MASTER)
		or croak "$!";
	$ldap->start_tls(verify => "require", cafile => "/etc/ssl/certs/Cluenet.pem")
		or croak "$!";
	my $sasl = Authen::SASL->new("GSSAPI");
	my $saslclient = $sasl->client_new("ldap", getfqdn(LDAP_MASTER));
	my $msg = $ldap->bind(sasl => $saslclient);
	$msg->code and die "error: ".$sasl->error;
	return $ldap;
}

sub connect_anon {
	my $ldap = Net::LDAP->new(LDAP_HOST)
		or croak "$!";
	$ldap->bind;
	return $ldap;
}

our $LDAP_CONN_AUTH;
our $LDAP_CONN_ANON;

sub ldap_connect_auth {
	return $LDAP_CONN_AUTH //= connect_auth;
}

sub ldap_connect_anon {
	return $LDAP_CONN_ANON //= $LDAP_CONN_AUTH // connect_anon;
}

sub is_group_member {
	my ($ldap, $user, $group) = @_;
	
	my $is_member = 0;
	my $res = $ldap->search(base => $group, scope => "base",
		filter => q(objectClass=*), attrs => ["member"]);
	$res->is_error and return 0;
	for my $entry ($res->entries) {
		$is_member += grep {user_from_dn($_) eq $user} $entry->get_value("member");
	}
	return $is_member;
}

# Get and cache LDAP authzid
sub whoami {
	if (!defined $whoami) {
		$whoami = (shift)->who_am_i->response;
		$whoami =~ s/^u://;
		$whoami =~ s/^dn:uid=(.+?),.*$/$1/;
	}
	return $whoami;
}

sub ldap_errmsg {
	my ($msg, $dn) = @_;
	my $text = "LDAP error: ".$msg->error."\n";
	if ($dn) {
		$text .= "\tfailed: $dn\n";
	}
	if ($msg->dn) {
		$text .= "\tmatched: ".$msg->dn."\n";
	}
	$text;
}

1;
