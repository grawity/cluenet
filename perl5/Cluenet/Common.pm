#!perl
package Cluenet::Common;
use warnings;
use strict;
use base "Exporter";

use Authen::Krb5;
use Carp;
use IO::Handle;
use Sys::Hostname;
use Socket::GetAddrInfo qw(:newapi getaddrinfo);
use User::pwent;

our @EXPORT = qw(
	canon_host
	getfqdn
	is_cluenet_user
	is_valid_user
	pwgen
	read_line
	server_fqdn
	);

sub BASEDIR	{ $ENV{CLUENET_DIR} // (-d "/cluenet" ? "/cluenet" : $ENV{HOME}."/cluenet") }
sub CONFIG_DIR	{ $ENV{CLUENET_CONFIG} // BASEDIR."/etc" }

sub read_line {
	my ($file) = @_;
	if (open my $fh, "<", $file) {
		chomp(my $line = $fh->getline);
		$fh->close;
		return $line;
	} else {
		croak "$!";
	}
}

sub pwgen {
	my $len = shift // 12;
	my @chars = ('A'..'Z', 'a'..'z', '0'..'9');
	my $chars = @chars;
	return join "", map {$chars[int rand $chars]} 1..$len;
}

#

sub is_valid_user {
	my $pw = getpwnam(shift);
	return defined $pw and $pw->uid >= 1000;
}

sub is_cluenet_user {
	my $pw = getpwnam(shift);
	return defined $pw and $pw->uid >= 25000;
}

#

sub getfqdn {
	return (gethostbyname(shift // hostname))[0];
}

sub canon_host {
	my $host = shift // hostname;
	my %hint = (flags => Socket::GetAddrInfo->AI_CANONNAME);
	my ($err, @ai) = getaddrinfo($host, "", \%hint);
	return $err ? $host : ((shift @ai)->{canonname} // $host);
}

sub lookup_host {
	my ($host) = @_;
	my @addrs = ();
	my $r = Net::DNS::Resolver->new;

	my $query = $r->query($host, "A");
	if ($query) { push @addrs, $_->address for $query->answer }

	$query = $r->query($host, "AAAA");
	if ($query) { push @addrs, $_->address for $query->answer }

	return @addrs;
}

sub server_fqdn {
	my ($host) = @_;
	return ($host =~ /\./) ? $host : "$host.cluenet.org";
}

1;
