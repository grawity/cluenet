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
	dns_match
	dns_match_zone
	dns_qualify

	canon_host
	getfqdn
	is_cluenet_user
	is_valid_user
	pwgen
	read_line
	server_fqdn
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

=item dns_qualify($name, $zone) -> $fqdn

Qualifies the subgiven DNS $name, which may be "@".

=cut

sub dns_qualify {
	my ($domain, $zone, $root) = @_;
	$root //= 1;
	if ($root and length($zone) and $zone !~ /\.$/) {
		$zone .= ".";
	}
	return $zone	if $domain eq '@';
	return $domain	if $domain =~ /\.$/;
	return $domain.".".$zone;
}

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
	carp "canon_host: obsolete, use getfqdn()";
	my $host = shift // hostname;
	my %hint = (flags => Socket::GetAddrInfo->AI_CANONNAME);
	my ($err, @ai) = getaddrinfo($host, "", \%hint);
	return $err ? $host : ((shift @ai)->{canonname} // $host);
}

sub lookup_host {
	carp "lookup_host: obsolete";
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
	carp "server_fqdn: obsolete";
	# TODO: hack dns_qualify to not return final dot?
	my ($host) = @_;
	return ($host =~ /\./) ? $host : "$host.cluenet.org";
}

1;
