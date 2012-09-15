#!perl
package Cluenet::Kerberos;
use warnings;
use strict;
use base "Exporter";
use Authen::Krb5;
use Authen::Krb5::Simple;
use Carp;
use Cluenet::Common;
use File::Spec;
use File::stat;
use File::Temp qw(tempfile);
use User::pwent;

our @EXPORT = qw(
	krb5_kuserok
	krb5_canonuser
	krb5_checkpass
	kinit_as_user
	kinit_as_service
	);

our $krb5_ctx = Authen::Krb5::init_context;

sub parse_principal {
	Authen::Krb5::parse_name(shift);
}

sub unparse_principal {
	my $p = shift;
	join("@", join("/", $p->data), $p->realm);
}

sub krb5_kuserok {
	my ($authzid, $princ) = @_;

	return 1 if $princ =~ m|.+/admin\@CLUENET\.ORG$|;

	my $pw = getpwnam($authzid);
	if (!defined $pw) {
		return 0;
	}

	my $file = File::Spec->catfile($pw->dir, ".k5login");

	#my $stat = stat($file);
	#if (!$stat or !($stat->uid == 0 or $stat->uid == $pw->uid)) {
	#	return $princ eq krb5_canonuser($authzid);
	#}

	if (open my $fh, "<", $file) {
		while (<$fh>) {
			chomp;
			if ($_ eq $princ) {
				close($fh);
				return 1;
			}
		}
	} else {
	#	return 0;
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

sub krb5_checkpass {
	my ($server, $user, $pass) = @_;
	my $krb = Authen::Krb5::Simple->new;
	return $krb->authenticate($user, $pass);
}

sub krb5_have_tgt {
	system("klist", "-s", "-5") == 0;
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

package Authen::Krb5::Principal;
use overload '""' => \&unparse;
use Carp;

sub new {
	my ($class, $princ) = @_;
	Authen::Krb5::parse_name($princ // croak "Usage: ${class}>new(principal)");
}

sub unparse {
	Cluenet::Kerberos::unparse_principal(shift);
}

1;
