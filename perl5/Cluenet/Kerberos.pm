#!perl
package Cluenet::Kerberos;
use warnings;
use strict;
use base "Exporter";

use Authen::Krb5;
use Carp;
use Cluenet::Common;
use File::Spec;
use File::stat;
use File::Temp qw(tempfile);
use User::pwent;

our @EXPORT = qw(
	krb5_kuserok
	krb5_canonuser
	krb5_ensure_tgt
	kinit_as_user
	kinit_as_service
	);

our $krb5_ctx = Authen::Krb5::init_context;

sub krb5_kuserok {
	my ($authzid, $princ) = @_;
	return 1 if $princ =~ m|.+/admin\@CLUENET\.ORG$|;
	my $pw = getpwnam($authzid) // return 0;
	my $file = File::Spec->catfile($pw->dir, ".k5login");
	my $stat = stat($file);
	if ($stat and ($stat->uid == 0 or $stat->uid == $pw->uid)) {
		if (open my $fh, "<", $file) {
			while (<$fh>) {
				chomp;
				return 1 if $_ eq $princ;
			}
		}
		return 0;
	} else {
		return $princ eq krb5_canonuser($authzid);
	}
}

sub krb5_canonuser {
	my $princ = shift;
	if ($princ !~ /@/) {
		$princ .= '@'.Authen::Krb5::get_default_realm;
	}
	return $princ;
}

sub krb5_ensure_tgt {
	if (system("klist", "-5s") > 0) {
		warn "Kerberos 5 ticket needed.\n";
		system("kinit");
	}
	if (system("klist", "-5s") > 0) {
		die "Authentication failed.\n";
	}
}

sub new_ccache {
	my $path = (tempfile("krb5cc_rd_XXXXXXXX", DIR => "/tmp"))[1];
	my $ccache = Authen::Krb5::cc_resolve("FILE:$path")
		or croak "Unable to resolve Kerberos ccache";
	return $ccache;
}

sub kinit_as_user {
	my ($client, %opts) = @_;
	my $princ = Authen::Krb5::parse_name($client);
	kinit($princ, %opts);
}

sub kinit_as_service {
	my ($service, %opts) = @_;
	my $host = $opts{hostname} // getfqdn;
	my $princ = Authen::Krb5::sname_to_principal($host, $service, KRB5_NT_SRV_HST);
	kinit($princ, %opts);
}

sub kinit {
	my ($princ, %opts) = @_;

	my ($cred, $ccache);

	if (defined $opts{keytab}) {
		my $ktab = Authen::Krb5::kt_resolve($opts{keytab});
		$cred = Authen::Krb5::get_init_creds_keytab($princ, $ktab);
	}
	elsif (defined $opts{password}) {
		$cred = Authen::Krb5::get_init_creds_password($princ, $opts{password});
	}
	else {
		croak "Either keytab or password is required";
	}

	if (!defined $cred) {
		die "Kerberos credential acquisition failed\n";
	}

	$ccache = new_ccache();
	$ccache->initialize($princ);
	$ccache->store_cred($cred);
	return $ccache;
}

1;
