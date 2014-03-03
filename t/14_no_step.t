#!perl 

use strict;
use Test::More tests => 3;
use Data::Dumper;
use FindBin;

BEGIN {
    use_ok( 'Data::Validate::WithYAML' );
}

my $validator = Data::Validate::WithYAML->new(
    $FindBin::Bin . '/test6.yml',
    no_steps => 1,
);

my %positive_check = ();
my %positive       = (
    email   => 'test@test.de',
    plz     => 'hallo',
    country => 'DE',
    age2    => 20,
    admin   => 'superuser',
);

my %errors_positive = $validator->validate( %positive );
is_deeply \%errors_positive, \%positive_check, 'correct values';

my %negative_check = ( email => 'Email is not correct', age => 'age must be either 1 or 2' );
my %negative       = (
    email   => 'test@test.de235235',
    plz     => 'hallo',
    country => 'DE',
    age     => 3,
    age2    => 20,
    admin   => 'superuser',
);

my %errors_negative = $validator->validate( %negative );
is_deeply \%errors_negative, \%negative_check, 'negative values';

