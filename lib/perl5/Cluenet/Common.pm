#!perl
package Cluenet::Common;
use base "Exporter";
use common::sense;
use Carp;
use IO::Handle;
use Socket::GetAddrInfo qw(:constants getaddrinfo getnameinfo);
use Sys::Hostname;
use User::pwent;

our @EXPORT = qw(
	dns_canonical
	dns_match
	dns_match_zone
	dns_qualify
	getfqdn
	make_server_fqdn
	file_read_line
	gen_passwd
	is_valid_user
	is_global_user
);

=over

=item * dns_match($domain, $subdomain) -> $matched

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

=item * dns_match_zone($domain, @zones) -> @zones

Finds the most specific zone that $domain belongs to.

=cut

sub dns_match_zone {
	my ($domain, @zones) = @_;
	my @matches = sort {length $b <=> length $a}
		grep {dns_match($_, $domain)} @zones;
	return wantarray ? @matches : shift(@matches);
}

=item * dns_qualify($name, $zone, $relative=1) -> $fqdn

Qualifies the given DNS $name, which may be "@".

If $relative > 0, the final dot will not be added (and will be removed if present).

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

=item * dns_canonical($name) -> $fqdn

Returns the "canonical name" of a given hostname, according to [reverse] DNS.

=cut

sub dns_canonical {
	my $name = shift // hostname;
	my ($err, @ai) = getaddrinfo($name, undef);
	for my $ai (@ai) {
		my ($err, $host) = getnameinfo($ai->{addr}, NI_NAMEREQD, NIx_NOSERV);
		return $host if !length($err);
	}
	warn "Could not resolve rDNS for $name, fallback to cname\n";
	return $ai[0]->{canonname};
}

=item * getfqdn() -> $fqdn

Returns the "canonical name" of current system, according to DNS.

=cut

sub getfqdn {
	return (gethostbyname(shift // hostname))[0];
}

=item * make_server_fqdn($name) -> $fqdn

Converts a Cluenet hostname into a FQDN, appending ".cluenet.org" if necessary,
ignoring reverse DNS.

=cut

sub make_server_fqdn {
	my $name = shift;
	return dns_match("cluenet.org", $name)
		? dns_qualify($name, "", 1)
		: dns_qualify($name, "cluenet.org", 1);
}

=item * file_read_line($file) -> $line

Read a single line from a file.

=cut

sub file_read_line {
	my ($file) = @_;
	if (open my $fh, "<", $file) {
		chomp(my $line = $fh->getline);
		$fh->close;
		return $line;
	} else {
		croak "$!";
	}
}

=item * gen_passwd([$length]) -> $password

Generate a random password.

=cut

sub gen_passwd {
	my $len = shift // 12;
	my @chars = ('A'..'Z', 'a'..'z', '0'..'9');
	my $chars = @chars;
	return join "", map {$chars[int rand $chars]} 1..$len;
}

sub is_valid_user {
	my $pw = getpwnam(shift);
	return defined $pw && $pw->uid >= 1000;
}

sub is_global_user {
	my $pw = getpwnam(shift);
	return defined $pw && $pw->uid >= 25000;
}

1;
