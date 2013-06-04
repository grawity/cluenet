package Cluenet::Common;
use warnings;
use strict;
use base "Exporter";

use Carp;
use IO::Handle;
use Socket::GetAddrInfo qw(:constants getaddrinfo getnameinfo);
use Sys::Hostname;

=head1 Cluenet::Common

Miscellaneous functions that don't have large dependencies.

=cut

our @EXPORT = qw(
	dns_canonical
	dns_fqdn
	dns_match
	dns_match_zone
	dns_qualify
	host_to_fqdn
	file_read_line
	gen_passwd
);

=head2 dns_match($domain, $subdomain) -> bool $matched

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

=head2 dns_match_zone($domain, @zones) -> @zones

Finds all zones that $domain belongs to, starting with most specific.

=cut

sub dns_match_zone {
	my ($domain, @zones) = @_;

	my @matches =
		sort {length $b <=> length $a}
		grep {dns_match($_, $domain)}
		@zones;

	return @matches;
}

=head2 dns_qualify($name, $zone, $relative=1) -> $fqdn

Qualifies the given DNS $name, which may be "@".

If $relative >= 1, the final dot will not be added (and will be removed if
present).

If $relative >= 2, names containing at least that many components will be
considered qualified.

Names ending with a . are always considered qualified.

=cut

sub dns_qualify {
	my ($domain, $zone, $relative) = @_;

	if ($relative) {
		$zone =~ s/\.$//;
		return $zone	if $domain eq '@';
		return $domain	if $domain =~ s/\.$//;
		my $ndots = $domain =~ tr/.//;
		return $domain	if $relative > 1 && $relative <= $ndots+1;
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

=head2 dns_canonical($name) -> $fqdn

Returns the "canonical name" of a given hostname, according to reverse DNS.

=cut

sub dns_canonical {
	my $name = shift;

	my ($err, @ai) = getaddrinfo($name, 0);
	for my $ai (@ai) {
		my ($err, $host) = getnameinfo($ai->{addr}, NI_NAMEREQD);
		return $host unless length($err);
	}
	warn "Could not resolve rDNS for $name, fallback to cname\n";
	return $ai[0]->{canonname};
}

=head2 dns_fqdn([$name]) -> $fqdn

Returns the FQDN of given hostname or current system -- but not necessarily the
reverse DNS name (e.g. it sometimes doesn't follow cnames).

=cut

sub dns_fqdn {
	my $name = shift // hostname;

	return (gethostbyname($name))[0];
}

=head2 host_to_fqdn($name) -> $fqdn

Converts a Cluenet hostname into a FQDN by appending ".cluenet.org" if
necessary (ignoring reverse DNS).

    equal -> equal.cluenet.org

    example.tld -> example.tld

=cut

sub host_to_fqdn {
	my $name = shift;

	return dns_qualify($name, "cluenet.org", 2);
}

=head2 file_read_line($file) -> $line

Read a single line from a file.

=cut

sub file_read_line {
	my $file = shift;

	if (open my $fh, "<", $file) {
		chomp(my $line = $fh->getline);
		$fh->close;
		return $line;
	} else {
		croak "$!";
	}
}

=head2 gen_passwd([$length]) -> $password

Generate a random password.

=cut

sub gen_passwd {
	my $len = shift // 12;

	my @chars = ('A'..'Z', 'a'..'z', '0'..'9');
	my $num = @chars;

	return join "", map {$chars[int rand $num]} 1..$len;
}

1;
