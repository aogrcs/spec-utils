package C::StructureSet;
use Moose;

use C::Structure;
use Local::C::Transformation qw(:RE);
use namespace::autoclean;

use re '/aa';

extends 'C::Set';
with    'C::Parse';

has '+set' => (
   isa => 'ArrayRef[C::Structure]',
);

sub parse
{
   my $self = shift;
   my $area = $_[1];
   my %structures;

   my $name = qr!(?<sname>[a-zA-Z_]\w*)!;
   
   while ( ${$_[0]} =~ m/^${h}*+
         (struct|union)
         ${s}++
            $name
         ${s}*+
         (?>
            (?<sbody>
            \{
               (?:
                  (?>[^\{\}]+)
                  |
                  (?&sbody)
               )*
            \}
            )
         )${s}*+;
      /gmpx) {
      my $name = $+{sname};

      carp("Repeated defenition of structure $name")
         if (exists $structures{$name});

      $structures{$name} = C::Structure->new(
                                 name => $name,
                                 code => ${^MATCH},
                                 type => $1,
                                 area => $area
                           );
   }

   return $self->new(set => [values %structures]);
}


__PACKAGE__->meta->make_immutable;

1;