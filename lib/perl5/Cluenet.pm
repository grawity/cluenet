package Cluenet;
use warnings;
use strict;

=head1 Cluenet

Constants aren't exported – they're to be used via Cluenet::FOO

=cut

use constant {
	LDAP_HOST		=> "ldap://ldap.cluenet.org",
	KADM_HOST		=> "virgule.cluenet.org",
	API_PRINC		=> undef,
	API_KEYTAB		=> undef,
};

1;
