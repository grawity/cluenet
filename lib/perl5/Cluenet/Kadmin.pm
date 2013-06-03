package Cluenet::Kadmin;
use feature qw(state);
use warnings;
use strict;
use base "Exporter";

use Authen::Krb5;
use Authen::Krb5::Admin qw(:constants);
use Carp;
use Cluenet;
use Cluenet::Kerberos;

our @EXPORT = qw(
	kadm_create_principal
);

=head2 kadm_get_config() -> $config

Return a singleton Authen::Krb5::Admin::Config object for the CLUENET.ORG realm.

=cut

sub kadm_get_config {
	state $config;
	if (!defined $config) {
		$config = Authen::Krb5::Admin::Config->new;
		$config->realm("CLUENET.ORG");
		$config->admin_server(Cluenet::KADM_HOST);
	}
	return $config;
}

=head2 kadm_connect_auth() -> $kadm

Connect to Cluenet's kadmin server using the environment ccache.

This currently depends on the external `kvno` utility. Sigh.

=cut

sub kadm_connect_auth {
	my $ccache = Authen::Krb5::cc_default;
	my $config = kadm_get_config;
	system("kvno", "-q", KADM5_ADMIN_SERVICE.'@CLUENET.ORG');
	my $kadm = Authen::Krb5::Admin->init_with_creds(
			$ccache->get_principal->unparse,
			$ccache,
			KADM5_ADMIN_SERVICE,
			$config);
	$kadm || croak Authen::Krb5::Admin::error;
	return $kadm;
}

=head2 kadm_connect_mgmt() -> $kadm

Connect to Cluenet's kadmin server using configured API principal & keytab.

=cut

sub kadm_connect_mgmt {
	my $config = kadm_get_config;
	my $kadm = Authen::Krb5::Admin->init_with_skey(
			Cluenet::API_PRINC,
			Cluenet::API_KEYTAB,
			KADM5_ADMIN_SERVICE,
			$config);
	$kadm || croak Authen::Krb5::Admin::error;
	return $kadm;
}

=head2 kadm_create_principal($kadm, $princ, $pass)

Create a Kerberos principal for a user.

=cut

sub kadm_create_principal {
	my ($kadm, $princ, $pass) = @_;

	my $krb5_princ = Authen::Krb5::parse_name($princ);

	my $kadm_princ = Authen::Krb5::Admin::Principal->new;
	$kadm_princ->principal($krb5_princ);

	if ($princ =~ m|/admin@|) {
		$kadm_princ->policy("admin");
	} else {
		$kadm_princ->policy("default");
	}

	$kadm->create_principal($kadm_princ, $pass)
		or croak Authen::Krb5::Admin::error;
}

1;
