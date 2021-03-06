package C::Util::Cycle;

use warnings;
use strict;

use re '/aa';

use Exporter qw(import);
use Scalar::Util qw(blessed);
use C::Util::Transformation qw(:RE);
use Local::String::Util qw(trim);

our @EXPORT = qw/resolve/;

sub resolve_macro_macro ($$$)
{
   my ($graph, @obj) = @_;
   #my @name  = map $_->name, @obj;

   # errors in binding
   #if ($obj[0]->args) {
   #   if ($obj[1]->code !~ m/\b$name[0]\s*+\(/) {
   #      $g->delete_edge($obj[0]->id, $obj[1]->id)
   #   }
   #}
   #if ($obj[1]->args) {
   #   if ($obj[0]->code !~ m/\b$name[1]\s*+\(/) {
   #      $g->delete_edge($obj[1]->id, $obj[0]->id)
   #   }
   #}
   
   $graph->delete_edge($obj[0]->id, $obj[1]->id);

   1
}

sub resolve_structure_structure ($$$)
{
   my ($graph, @obj) = @_;
   my @ctype = map $_->type, @obj;
   my @name  = map $_->name, @obj;
   if ((blessed($obj[0]) eq 'C::Typedef') && (defined $obj[0]->inside)) {
      $name[0] = $obj[0]->inside->[1];
   }
   if ((blessed($obj[1]) eq 'C::Typedef') && (defined $obj[1]->inside)) {
      $name[1] = $obj[1]->inside->[1];
   }

   #multiple fields 'struct test; struct test *;' possible
   if ($obj[1]->code !~ m/$ctype[0]${s}++$name[0]\b${s}*+[^*]/) {
      $graph->delete_edge($obj[0]->id, $obj[1]->id);
      return 1
   }
   if ($graph->has_edge($obj[1]->id, $obj[0]->id)) {
      if ($obj[0]->code !~ m/$ctype[1]${s}++$name[1]\b${s}*+[^*]/) {
         $graph->delete_edge($obj[1]->id, $obj[0]->id);
         return 1
      }
   }

   0
}

sub resolve_function_function
{
   my ($graph, @obj) = @_;
   my @ids = ($obj[0]->id, $obj[1]->id);
   my @rids = reverse @ids;
   my $redge = $graph->has_edge(@rids);
   my $spec_edge  = $graph->get_edge_attribute(@ids, 'spec_edge');
   my $rspec_edge = $graph->get_edge_attribute(@rids, 'spec_edge');

   if ($redge) { # Если есть обратная дуга
      if ($spec_edge) {
         # Можно без проблем разъединить, но не будет выводиться последней
         #$graph->delete_edge(@ids);
         #return 1;
         return 0;
      } else {  # Если это не спецификационная связь
         if (!$rspec_edge) { # Если обратная не спецификационная
            $obj[1]->add_fw_decl($obj[0]->declaration);
            $graph->delete_edge(@ids);
         } else {
            $obj[0]->add_fw_decl($obj[1]->declaration);
            $graph->delete_edge(@ids);
         }
         return 1;
      }
   } else {
      if (!$spec_edge) { # Можно разорвать если цикл
         $obj[1]->add_fw_decl($obj[0]->declaration);
         $graph->delete_edge(@ids);
         return 1;
      }
   }

   0
}

sub resolve_structure_typedef ($$$)
{
   my ($graph, @obj) = @_;

   unless (defined $obj[1]->inside) {
      $graph->delete_edge($obj[0]->id, $obj[1]->id);
      return 1;
   } else {
      my $t = $obj[1]->inside->[0];
      $t = 'structure' if $t eq 'struct' || $t eq 'union';
      my $sub = 'resolve_structure_' . $t;
      {
         no strict 'refs';

         if (defined &{ $sub }) {
            goto &{ $sub }
         } else {
            warn "Function $sub in " . __PACKAGE__ . " package doesn't exist. Skipping the call.\n"
         }
      }

   }
}

sub resolve_acslcomment_acslcomment ($$$)
{
   my ($graph, @obj) = @_;
   my @id = ($obj[0]->id, $obj[1]->id);

   if ($graph->has_edge(reverse @id)) {
      if ($obj[0]->replacement_id < $obj[1]->replacement_id) {
         $graph->delete_edge(@id);
      }# else {
      #   $graph->delete_edge(reverse @id);
      #}
      return 1;
   }
   
   0
}

sub resolve_typedef_structure
{
   0
}

sub resolve_typedef_typedef
{
   my (undef, @obj) = @_;

   my $t0 = defined $obj[0]->inside ? $obj[0]->inside->[0] : 'typedef';
   my $t1 = defined $obj[1]->inside ? $obj[1]->inside->[0] : 'typedef';

   $t0 = 'structure' if $t0 eq 'struct' || $t0 eq 'union';
   $t1 = 'structure' if $t1 eq 'struct' || $t1 eq 'union';

   if ($t0 ne 'typedef' || $t1 ne 'typedef') {
      my $sub = join('_', ('resolve', $t0, $t1));
      {
         no strict 'refs';

         if (defined &{ $sub }) {
            goto &{ $sub }
         } else {
            warn "Function $sub in " . __PACKAGE__ . " package doesn't exist. Skipping the call.\n"
         }
      }
   }

   0
}

sub resolve_function_global
{
   0
}

sub resolve_global_function
{
   my ($graph, @obj) = @_;
   my $global_decl = trim($obj[0]->type) . " " . $obj[0]->name . ";";
   if (defined $obj[0]->modifier) {
      $global_decl = trim($obj[0]->modifier) . " " . $global_decl;
   }
   $obj[1]->add_fw_decl($global_decl);
   $graph->delete_edge($obj[0]->id, $obj[1]->id);
   1
}

sub resolve
{
   my ($graph, @cycle) = @_;

   if (@cycle == 1) {
      $graph->delete_edge(@cycle[0,0])
   } else {
      my @objs = map { $graph->get_vertex_attribute($_, 'object') } @cycle;
      my @obj_pairs;
      {
         my $prev = $objs[-1];
         foreach (@objs) {
            push @obj_pairs, [$prev, $_];
            $prev = $_;
         }
      }

      my $ok = 0;
LOOP: foreach (@obj_pairs) {
         my @t = map blessed $_, @$_;

         my $trans = sub { lc(substr($_[0], 3)) };
         my $sub = join('_', ('resolve', $trans->($t[0]), $trans->($t[1])));

         {
            no strict 'refs';

            if (defined &{ $sub }) {
               if (&{ $sub }($graph, @$_)) {
                  $ok = 1;
                  last LOOP
               }
            } else {
               warn "Function $sub in " . __PACKAGE__ . " package doesn't exist. Skipping the call.\n"
            }
         }
      }

      unless ($ok) {
         warn "Can't properly resolve cycle.\n";
         #my @objs = map { $graph->get_vertex_attribute($_, 'object') } @cycle;
         #use Data::Printer;
         #p @objs;
         #exit;
         $graph->delete_edge(@cycle[0,-1])
      }
   }
}

1;
