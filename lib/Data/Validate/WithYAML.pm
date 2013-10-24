package Data::Validate::WithYAML;

use strict;
use warnings;

use Carp;
use YAML::Tiny;

# ABSTRACT: Validation framework that can be configured with YAML files

our $VERSION = '0.13';
our $errstr  = '';

=head1 SYNOPSIS

Perhaps a little code snippet.

    use Data::Validate::WithYAML;

    my $foo = Data::Validate::WithYAML->new( 'test.yml' );
    my %map = (
        name     => 'Test Person',
        password => 'xasdfjakslr453$',
        plz      => 64569,
        word     => 'Herr',
        age      => 55,
    );
    
    for my $field ( keys %map ){
        print "ok: ",$map{$field},"\n" if $foo->check( $field, $map{$field} );
    }

data.yml

  ---
  step1:
      name:
          type: required
          length: 8,122
      password:
          type: required
          length: 10,
      plz:
          regex: ^\d{4,5}$
          type: optional
      word:
          enum:
              - Herr
              - Frau
              - Firma
      age:
          type: required
          min: 18
          max: 65
  

=head1 METHODS

=head2 new

  my $foo = Data::Validate::WithYAML->new( 'filename' );
  my $foo = Data::Validate::WithYAML->new(
      'filename',
      allow_subs => 1,
      no_steps   => 1,
  );

creates a new object.

=cut

sub new{
    my ($class,$filename,%args) = @_;
    
    my $self = {};
    bless $self,$class;
    
    $self->{__optional__} = {};
    $self->{__required__} = {};
    
    $self->_allow_subs( $args{allow_subs} );
    $self->_no_steps( $args{no_steps} );
    $self->_yaml_config( $filename ) or return undef;
    
    return $self;
}

sub _optional {
    my ($self) = @_;
    $self->{__optional__};
}

sub _required {
    my ($self) = @_;
    $self->{__required__};
}

sub _no_steps {
    my ($self, $no_steps) = @_;
    $self->{__no_steps__} = $no_steps if @_ == 2;;
    $self->{__no_steps__};
}

=head2 set_optional

This method makes a field optional if it was required

=cut

sub set_optional {
    my ($self,$field) = @_;
    
    my $value = delete $self->_required->{$field};
    if( $value ) {
        $self->_optional->{$field} = $value;
    }
}

=head2 set_required

This method makes a field required if it was optional

=cut

sub set_required {
    my ($self,$field) = @_;
    
    my $value = delete $self->_optional->{$field};
    if( $value ) {
        $self->_required->{$field} = $value;
    }
}

=head2 validate

This subroutine validates one form. You have to pass the form name (key in the
config file), a hash with fieldnames and its values

    my %fields = (
        username => $cgi->param('user'),
        passwort => $password,
    );
    $foo->validate( 'step1', %fields );

=cut

sub validate{
    my $self = shift;

    my ($part, %hash);

    if ( @_ && @_ % 2 == 0 ) {
        %hash = @_;
        $part = '';
    }
    else {
        ($part, %hash) = @_;
    }

    my @fieldnames  = $self->fieldnames( $part );
    
    my %errors;
    my %fields;
    my $optional = $self->_optional;
    my $required = $self->_required; 
    
    for my $name ( @fieldnames ) {
        $fields{$name} = $optional->{$name} if exists $optional->{$name};
        $fields{$name} = $required->{$name} if exists $required->{$name};

        next if !$fields{$name};
        next if $fields{$name}->{no_validate};
        
        my $value = $hash{$name};
        
        my $depends_on = $fields{$name}->{depends_on};
        if ( $depends_on ) {
            if ( !$hash{$depends_on} ) {
                $errors{$name} = $self->message( $name );
                next;
            }
            
            my $depends_on_value = $hash{$depends_on};
            my $cases            = $fields{$name}->{case} || {};
            
            #if ( !$cases->{$value} ) {
            #    $errors{$name} = $self->message( $name );
            #    next;
            #}
            
            $fields{$name} = $cases->{$depends_on_value} if $cases->{$depends_on_value};
        }
        
        $fields{$name}->{type} ||= 'optional';
        my $success = $self->check( $name, $hash{$name}, $fields{$name} );
        if ( !$success ) {
            $errors{$name} = $self->message( $name );
        }
    }
    
    return %errors;
}

=head2 fieldnames

=cut

sub fieldnames{
    my $self = shift;

    my ($step, %options);

    if ( @_ && @_ % 2 == 0 ) {
        %options = @_;
        $step = '';
    }
    else {
        ($step, %options) = @_;
    }

    my @names;
    if( defined $step ){
        @names = @{ $self->{fieldnames}->{$step} || [] };
    }
    else{
        for my $step ( keys %{ $self->{fieldnames} } ){
            push @names, @{ $self->{fieldnames}->{$step} };
        }
    }
    
    if ( $options{exclude} ) {
        my %hash;
        @hash{@names} = (1) x @names;
        
        delete @hash{ @{$options{exclude}} };
        
        @names = keys %hash;
    }

    return @names;
}

=head2 errstr

=cut

sub errstr{
    my ($self) = @_;
    return $errstr;
}

=head2 message

returns the message if specified in YAML

  $obj->message( 'fieldname' );

=cut

sub message {
    my ($self,$field) = @_;
    
    my $subhash = $self->_required->{$field} || $self->_optional->{$field};
    my $message = "";
    
    if ( $subhash->{message} ) {
        $message = $subhash->{message};
    }

    $message;
}

=head2 check_list

  $obj->check_list('fieldname',['value','value2']);

Checks if the values match the validation criteria. Returns an arrayref with
checkresults:

    [
        1,
        0,
    ] 

=cut

sub check_list {
    my ($self,$field,$values) = @_;
    
    return if !$values;
    return if ref $values ne 'ARRAY';
    
    my @results;
    for my $value ( @{$values} ) {
        push @results, $self->check( $field, $value ) ? 1 : 0;
    }
    
    return \@results;
}

=head2 check

  $obj->check('fieldname','value');

checks if a value is valid. returns 1 if the value is valid, otherwise it
returns 0.

=cut

sub check{
    my ($self,$field,$value,$definition) = @_;
    
    my %dispatch = (
        min    => \&_min,
        max    => \&_max,
        regex  => \&_regex,
        length => \&_length,
        enum   => \&_enum,
        sub    => \&_sub,
    );
                
    my $subhash = $definition || $self->_required->{$field} || $self->_optional->{$field};
    
    if(
        ( $definition and $definition->{type} eq 'required' )
        or ( !$definition and exists $self->_required->{$field} )
        ){
        return 0 unless defined $value and length $value;
    }
    elsif( 
        ( ( $definition and $definition->{type} eq 'optional' ) 
        or ( !$definition and exists $self->_optional->{$field} ) )
        and (not defined $value or not length $value) ){
        return 1;
    }
    
    my $bool = 1;
    
    for my $key( keys %$subhash ){
        if( exists $dispatch{$key} ){
            unless($dispatch{$key}->($value,$subhash->{$key},$self)){
                $bool = 0;
                last;
            }
        }
        elsif( $key eq 'plugin' ){
            my $name     = $subhash->{$key};
            my $module   = 'Data::Validate::WithYAML::Plugin::' . $name;
            eval "use $module";
            
            if( not $@ and $module->can('check') ){
                my $retval = $module->check($value, $subhash);
                $bool = 0 unless $retval;
            }
            else{
                croak "Can't check with $module";
            }
        }
    }
    
    return $bool;
}

=head2 fieldinfo

Returns the config for the given field.

Your test.yml:

  ---
  age:
    type: required
    min: 18
    max: 65

Your script:

    my $info = $validator->fieldinfo( 'age' );

C<$info> is a hashreference then:

    {
        type => 'required',
        min  => 18,
        max  => 65,
    }

=cut

sub fieldinfo {
    my ($self, $field) = @_;

    my $info = $self->_required->{$field} || $self->_optional->{$field};
    return if !$info;

    return $info;
}

# read config file and parse required and optional fields
sub _yaml_config{
    my ($self,$file) = @_;
    
    if(defined $file and -e $file){
        $self->{config} = YAML::Tiny->read( $file ) or 
                (($errstr = YAML::Tiny->errstr()) && return undef);

        if ( $self->_no_steps ) {
            $self->_add_fields( $self->{config}->[0], '' );
        }
        else {
            for my $section(keys %{$self->{config}->[0]}){
                my $sec_hash = $self->{config}->[0]->{$section};
                $self->_add_fields( $sec_hash, $section );
            }
        }
    }
    elsif(defined $file){
        $errstr = 'file does not exist';
        return undef;
    }
    
    return $self->{config};
}

sub _add_fields {
    my ($self, $data, $section) = @_;

    for my $field( keys %$data ){
        if(exists $data->{$field}->{type} and
                  $data->{$field}->{type} eq 'required'){
            $self->_required->{$field} = $data->{$field};

            if( exists $self->_optional->{$field} ){
                delete $self->_optional->{$field};
            }
        }
        elsif( not exists $self->_required->{$field} ){
            $self->_optional->{$field} = $data->{$field};
        }

        push @{$self->{fieldnames}->{$section}}, $field;
    }
}

sub _min{
    my ($value,$min) = @_;
    return $value >= $min;
}

sub _max{
    my ($value,$max) = @_;
    return $value <= $max;    
}

sub _regex{
    my ($value,$regex) = @_;
    my $re = qr/$regex/;
    return ($value =~ $re);
}

sub _length{
    my ($value,$check) = @_;
    
    if($check =~ /,/){
        my ($min,$max) = $check =~ /\s*(\d+)?\s*,\s*(\d+)?/;
        my $bool = 1;
        if(defined $min and length $value < $min){
            $bool = 0;
        }
        if(defined $max and length $value > $max){
            $bool = 0;
        }
        return $bool;
    }
    else{
        return length $value > $check;
    }
}

sub _enum{
    my ($value,$list) = @_;
    return grep{ $_ eq $value }@$list;
}

sub _sub {
    my ($value,$sub,$self) = @_;
    $_ = $value;
    
    croak "Can't use user defined sub unless it is allowed" if !$self->_allow_subs;
    
    return eval "$sub";
}

sub _allow_subs {
    my ($self,$value) = @_;
    
    $self->{__allow_subs} = $value if @_ == 2;
    $self->{__allow_subs};
}

1;
