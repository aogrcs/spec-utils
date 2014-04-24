package C::MacroSet;
use Moose;

use Carp;
use C::Macro;
use namespace::autoclean;

use re '/aa';

extends 'C::Set';
with    'C::Parse';

has '+set' => (
   isa => 'ArrayRef[C::Macro]',
   handles => {
      map             => 'map',
      get_from_index  => 'get'
   }
);

has 'index' => (
   is => 'rw',
   isa => 'HashRef[Str]',
   lazy => 1,
   builder => '_rebuild_index',
   traits => ['Hash'],
   handles => {
      exists    => 'exists',
      keys      => 'keys',
      get_index => 'get'
   }
);

sub _rebuild_index
{
   my $i = 0;
   +{ $_[0]->map(sub { ($_->name, $i++) }) }
}

sub push
{
   my $self = shift;

   my $i = $#{$self->set};
   foreach (@_) {
      push @{$self->set}, $_;
      $self->index->{$_->name} = ++$i;
   }
}

sub ids
{
   [ $_[0]->map( sub { return [] unless $_; $_->get_code_ids }) ]
}

sub tags
{
   [ $_[0]->map( sub { return [] unless $_; $_->get_code_tags }) ]
}


sub delete
{
		delete $_[0]->set->[ $_[0]->get_index($_[1]) ];
      delete $_[0]->index->{ $_[1] };
}

sub get
{
   $_[0]->get_from_index($_[0]->get_index($_[1]))
}

#FIXME: only oneline defines currently allowed
sub parse
{
   my $self = shift;
   my $area = $_[1];
   my %defines;

   foreach(@{$_[0]}) {
      if (
         m/
            \A
            [ \t]*+
            \#
            [ \t]*+
            define
            [ \t]++
            (?<def>[a-zA-Z_]\w*+)
            (?:\([ \t]*(?<args>[^\)]*)\))?
            [ \t]*+
            (?<code>.*)\Z
         /xp) {
         my $name = $+{def};

         if (exists $defines{$name}) {
            warn("Repeated defenition of macro $name\n")
         } else {
            my $code = ${^MATCH};
            my $substitution = $+{code};
            my $args = undef;

            if (exists $+{args}) {
               $args = [ $+{args} =~ m/[a-zA-Z_]\w*+/g ]
            }

            $defines{$name} = C::Macro->new(name => $name, args => $args, code => $code, substitution => $substitution, area => $area)
         }
      } else {
         warn("Can't parse $_\n");
      }
   }

   return $self->new(set => [ values %defines ]);
}


__PACKAGE__->meta->make_immutable;

1;