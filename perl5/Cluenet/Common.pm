#!perl
package Cluenet::Common;
use common::sense;
use base "Exporter";

use Authen::Krb5;
use Carp;
use IO::Handle;
use Sys::Hostname;
use Socket::GetAddrInfo qw(:newapi getaddrinfo);
use User::pwent;

our @EXPORT = qw(
	dns_canonical
	dns_match
	dns_match_zone
	dns_qualify
	getfqdn
	make_server_fqdn

	is_cluenet_user
	is_valid_user
	pwgen
	read_line
	);

=over

=item dns_match($domain, $subdomain) -> $matched

Checks if DNS-like $subdomain equals or belongs to $domain.

=cut

sub dns_match {
	my @a = reverse split(/\./, lc shift);
	my @b = reverse split(/\./, lc shift);
	return 1 if !@a;
	return 0 if @a > @b;
	for my $i (0..$#a) {
		return 0 if $a[$i] ne $b[$i];
	}
	return scalar @a;
}

=item dns_match_zone($domain, @zones) -> @zones

Finds the most specific zone that $domain belongs to.

=cut

sub dns_match_zone {
	my ($domain, @zones) = @_;
	my @matches = sort {length $b <=> length $a}
		grep {dns_match($_, $domain)} @zones;
	return wantarray ? @matches : shift(@matches);
}

=item dns_qualify($name, $zone, $root=1) -> $fqdn

Qualifies the given DNS $name, which may be "@".
If $relative, the final dot will not be added (and will be removed if present).
If $relative > 1, names containing at least that many components will be considered qualified.
Names ending with a . are always considered qualified.

=cut

sub dns_qualify {
	my ($domain, $zone, $relative) = @_;
	if ($relative) {
		$zone =~ s/\.$//;
		return $zone	if $domain eq '@';
		return $domain	if $domain =~ s/\.$//;
		my $ndots = $domain =~ tr/.//;
		return $domain	if $relative > 1
			and $relative <= $ndots+1;
		return $domain	if $zone eq '';
		return $domain.".".$zone;
	} else {
		if (length($zone) and $zone !~ /\.$/) {
			$zone .= ".";
		}
		return $zone	if $domain eq '@';
		return $domain	if $domain =~ /\.$/;
		return $domain.".".$zone;
	}
}

=item dns_canonical($name) -> $fqdn

Returns the "canonical name" of a given hostname, according to [reverse] DNS.

=cut

sub dns_canonical {
	return (gethostbyname(shift // hostname))[0];
}

=item getfqdn() -> $fqdn

Returns the "canonical name" of current system, according to DNS.

Equivalent to dns_canonical(hostname).

=cut

sub getfqdn {
	return dns_canonical(hostname);
}

=item make_server_fqdn($name) -> $fqdn

Converts a Cluenet hostname into a FQDN, appending ".cluenet.org" if necessary,
ignoring reverse DNS.

=cut

sub make_server_fqdn {
	my $name = shift;
	return dns_match("cluenet.org", $name)
		? dns_qualify($name, "", 1)
		: dns_qualify($name, "cluenet.org", 1);
}

# Junk

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

1;
