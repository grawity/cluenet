#!perl
package Cluenet::Kadmin;
use base qw(Exporter);
use feature qw(state);
use strict;
use warnings;

use Authen::Krb5;
use Authen::Krb5::Admin qw(:constants);
use Carp;
use Cluenet;

our @EXPORT = qw(
	kadm_create_principal
);

sub kadm_get_config {
	state $config;
	if (!defined $config) {
		$config = Authen::Krb5::Admin::Config->new;
		$config->realm("CLUENET.ORG");
		$config->admin_server(Cluenet::KADM_HOST);
	}
	return $config;
}

sub kadm_connect_mgmt {
	my $config = kadm_get_config;
	my $kadm = Authen::Krb5::Admin->init_with_skey(
			Cluenet::API_PRINC,
			Cluenet::API_KEYTAB,
			KADM5_ADMIN_SERVICE, $config);
	$kadm || croak Authen::Krb5::Admin::error;
	return $kadm;
}

sub kadm_create_principal {
	my ($princ, $pass) = @_;

	my $krb5_princ = Authen::Krb5::parse_name($princ);
	my $kadm_princ = Authen::Krb5::Admin::Principal->new;
	$kadm_princ->principal($krb5_princ);
	if ($princ =~ m|/admin@|) {
		$kadm_princ->policy("admin");
	} else {
		$kadm_princ->policy("default");
	}

	my $kadm = kadm_connect_mgmt;
	my $r = $kadm->create_principal($kadm_princ, $pass);
	$r || croak Authen::Krb5::Admin::error;

	return 1;
}

1;
