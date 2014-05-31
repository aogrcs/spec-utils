package Local::GCC::Preprocess;

use strict;
use warnings;

use re '/aa';

use Exporter qw(import);
use IPC::Open2;
use Carp;
use Cwd qw(realpath);


our @EXPORT_OK = qw(
      get_macro
      preprocess
      preprocess_directives_noincl
      preprocess_directives
      preprocess_as_kernel_module
      preprocess_as_kernel_module_simpl
      preprocess_as_kernel_module_directives
      preprocess_as_kernel_module_get_macro_simpl
);


sub call_gcc
{
   my ($gcc_args, $code, $wantarray) = @_;
   my @res;
   my $res;

   my $pid = open2(\*GCC_OUT, \*GCC_IN, "gcc $gcc_args -");
   print GCC_IN $$code;
   close GCC_IN;

   if ($wantarray) {
      chomp(@res = <GCC_OUT>);
   } else {
      $res .= $_ while <GCC_OUT>;
   }

   close GCC_OUT;
   waitpid($pid, 0);
   die("GCC falls with error.\n") if $?;

   return $wantarray ? \@res : \$res;
}

sub get_macro
{
   call_gcc('-dM -E -P -nostdinc', @_)
}

sub preprocess
{
   call_gcc('-E -P -nostdinc', @_)
}

use constant ARRAY => ref [];
my $include_re = qr|#\h*+include\h*+[<"][^">]++[">]|;
my $include_mark = "//<ci_$$>";
sub _comment_includes
{
   ${$_[0]} =~ s|^\K(?=\h*+${include_re})|$include_mark|mg;
}

sub _uncomment_includes
{
   my $re = qr|^\K\Q${include_mark}\E(?=\h*+${include_re})|m;
   if ((ref $_[0]) eq ARRAY) {
      s/$re// foreach @{$_[0]}
   } else {
      ${$_[0]} =~ s/$re//g
   }
}

#excluding include directives
sub preprocess_directives_noincl
{
   my $code = ($_[1] ? ${$_[1]}: '') . "\n//<special_mark>\n" . ${$_[0]};

   _comment_includes(\$code);

   $code = call_gcc('-E -P -C -fdirectives-only -nostdinc ',
                     \$code,
                     $_[2]);

   _uncomment_includes($code);

   if ($_[2]) {
      my $ind = -1;
      for (my $i = 0; $i < $#$code; ++$i) {
         if ($code->[$i] eq '//<special_mark>') {
            $ind = $i;
            last
         }
      }
      die("Internal error. Can't find marker") if $ind == -1;

      [ splice(@$code, $ind + 1) ]
   } else {
      \substr( $$code,
               index($$code, '//<special_mark>') +
               length('//<special_mark>') +
               1
            )
   }
}

sub _generic_preprocess_directives
{
   my %files;
   my $current_file;

   my $code = call_gcc( shift,
                        \(($_[1] ? ${$_[1]}: '') . "\n//<special_mark>\n" . ${$_[0]}),
                        1);

   {
      my $ind = -1;
      for (my $i = 0; $i < $#$code; ++$i) {
         if ($code->[$i] eq '//<special_mark>') {
            $ind = $i;
            last
         }
      }
      die("Internal error. Can't find marker") if $ind == -1;

      $code = [ splice(@$code, $ind + 1) ];
   }

   my @order;
   foreach (@$code) {
      if (m/#\h++\d++\h++"([^"]++)"/) {
         $current_file = $1 eq "<stdin>" ? $1 : realpath($1);
         push @order, $current_file;
         next
      }

      push @{ $files{$current_file} }, $_
   }

   {
      my %uniq;
      @order = reverse grep { !$uniq{$_}++ } reverse @order;
   }

   foreach (keys %files) {
      $files{$_} = join("\n", @{ $files{$_} })
   }

   (\@order, \%files)
}

# directory
# code
# additional directives
sub preprocess_directives
{
   _generic_preprocess_directives('-E -CC -fdirectives-only -nostdinc ', @_)
}


my @kernel_include_path = qw(
arch/x86/include/
arch/x86/include/generated/
include/
include/generated/
arch/x86/include/uapi/
arch/x86/include/generated/uapi/
include/uapi/
include/generated/uapi/
);

my $last_path = '';
my $gcc_include_path = undef;
my $stdlib = undef;

sub form_gcc_kernel_include_path
{
   my $kdir_path = shift;

   if ($last_path eq $kdir_path && defined $gcc_include_path) {
      return $gcc_include_path
   }

   croak("$kdir_path is not a kernel directory.")
      unless -e "$kdir_path/Kbuild";

   $last_path = $kdir_path;
   $gcc_include_path = '';

   $gcc_include_path .= "-I ${kdir_path}/${_} "
      foreach @kernel_include_path;

   if (!defined $stdlib) {
      my @str = split "\n",  qx(gcc -print-search-dirs);
      $stdlib = substr($str[0], index($str[0], ': ') + 2) . 'include/';
   }

   $gcc_include_path .= "-I $stdlib";

   $gcc_include_path
}

sub _add_kernel_kconfig
{
   $_[0] = "#include <linux/kconfig.h>\n\n" . $_[0]
}

sub _add_kernel_defines
{
   $_[0] = "#define __KERNEL__ 1\n#define MODULE 1\n\n" . $_[0]
}

# kernel directory
# include directories
# code
# additional defines
sub preprocess_as_kernel_module_directives
{
   my ($kdir, $idir) = (shift, shift);

   _add_kernel_defines(${$_[0]});
   _add_kernel_kconfig(${$_[0]});

   _generic_preprocess_directives(
            '-E -CC -fdirectives-only -nostdinc ' .
            form_gcc_kernel_include_path($kdir)   .
            " -I " . join(" -I ", @$idir) . " ",
            @_[0,1])
}

sub preprocess_as_kernel_module
{
   my ($kdir, $idir) = (shift, shift);

   _add_kernel_defines(${$_[0]});
   _add_kernel_kconfig(${$_[0]});

   _generic_preprocess_directives(
            '-E -CC -nostdinc ' .
            form_gcc_kernel_include_path($kdir)   .
            " -I " . join(" -I ", @$idir) . " ",
            @_[0,1])
}

sub preprocess_as_kernel_module_simpl
{
   _add_kernel_defines(${$_[1]});
   _add_kernel_kconfig(${$_[1]});
   call_gcc('-E -P -nostdinc ' . form_gcc_kernel_include_path($_[0]), @_[1,2])
}

sub preprocess_as_kernel_module_get_macro_simpl
{
   _add_kernel_defines(${$_[1]});
   _add_kernel_kconfig(${$_[1]});
   call_gcc('-dM -E -P -nostdinc ' . form_gcc_kernel_include_path($_[0]), @_[1,2])
}


1;
