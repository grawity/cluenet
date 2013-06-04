package Cluenet;
use warnings;
use strict;

=head1 Cluenet

Constants and variables aren't exported – they're to be used as Cluenet::FOO
and $Cluenet::FOO.

=cut

our $LDAP_HOST = "ldap://ldap.cluenet.org";
our $KADM_HOST = "krb5-admin.cluenet.org";
our $API_PRINC = undef;
our $API_KEYTAB = undef;

1;
