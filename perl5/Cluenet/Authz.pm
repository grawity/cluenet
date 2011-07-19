#!perl
package Cluenet::Authz;
use common::sense;
use base "Exporter";
use Cluenet::LDAP;

our @EXPORT = qw(
	get_user_authorizations
	);

=sub

get_user_authorizations($user) -> @authorizedAbilities

=cut

sub get_user_authorizations {
	my ($user) = @_;
	my $ldap = ldap_connect_anon();
	my $dn = user_dn($user);
	my $res = $ldap->search(base => $dn, scope => "base",
		filter => q(objectClass=posixAccount),
		attrs => ["clueAuthorizedAbility"]);
	if ($res->is_error) {
		warn ldap_errmsg($res, $dn);
		return undef;
	}
	for my $entry ($res->entries) {
		return $entry->get_value("clueAuthorizedAbility");
	}
}

1;
