#!/usr/local/bin/perl -w

=head1 NAME

map.t - test VCP::Filter::map

=cut

use VCP::Dest;

@ISA = qw( VCP::Dest );

use strict ;

use Carp ;
use File::Spec ;
use Test ;
use VCP::TestUtils ;

## These next few are for in vitro testing
use VCP::Filter::map;
use VCP::Rev;

my @vcp = vcp_cmd ;

sub r {
   my ( $name, $branch_id ) = $_[0] =~ /\A(?:(.+?))?(?:<(.*)>)?\z/
      or die "Couldn't parse '$_[0]'";

   VCP::Rev->new(
      id        => $_[0],
      name      => $name,
      branch_id => $branch_id,
   )
}

my $filter;

my $r_out;

my $r_count;
my $r_received_count;

sub rev_count { $r_count = $_[1] }

sub _skip_rev {
    ++$r_received_count;
}

sub handle_rev {
    my $self = shift;
    my ( $rev ) = @_;
    ++$r_received_count;
    $r_out = join "", $rev->name || "", "<", $rev->branch_id || "", ">";
}


sub t {
    return skip "compilation failed", 1 unless $filter;

    my ( $expr, $expected ) = @_;

    $r_out = undef;
    $r_received_count = 0;
    $r_count = 0;

    $filter->handle_rev( r $expr );

    @_ = ( $r_out || "<<deleted>>", $expected || "<<deleted>>" );
    goto &ok;
}

my @tests = (
## In vitro tests
sub {
   eval { $filter = VCP::Filter::map->new( "",
   [
      '<b>',          '<B>',
      'a',            'A',
      'a',            'NONONO',
      'c<d>',         'C<D>',
      'xyz',          '<<keep>>',
      'x*',           '<<delete>>',
      's(*)v<(...)>', 'S$1V${2}Y<>',
      's(*)v<>',      'NONONO',
   ] ) }; 
   ok $filter ? 1 : $@, 1;
   $filter->dest( main->new ) if $filter;
},

sub { t "a<b>",     "a<B>"       },
sub { ok $r_received_count, 1 },
sub { t "a<c>",     "A<c>"       },
sub { ok $r_received_count, 1 },
sub { t "c<d>",     "C<D>"       },
sub { ok $r_received_count, 1 },
sub { t "c<e>",     "c<e>"       },
sub { ok $r_received_count, 1 },
sub { t "e<d>",     "e<d>"       },
sub { ok $r_received_count, 1 },
sub { t "xab",      undef        },
sub { ok $r_received_count, 1 },
sub { t "xyz",      "xyz<>"      },
sub { ok $r_received_count, 1 },
sub { t "Z<Z>",     "Z<Z>"       },
sub { ok $r_received_count, 1 },
sub { t "stuv<wx>", "StuVwxY<>"  },
sub { ok $r_received_count, 1 },

## In vivo tests
sub {
  eval {
     my $out ;
     my $infile = "t/test-revml-in-0-no-big-files.revml";
     ## $in and $out allow us to avoide execing diff most of the time.
     run [ @vcp, "vcp:-" ], \<<'END_VCP', \$out;
Source: t/test-revml-in-0-no-big-files.revml

Sort:

Destination: -

Map:
END_VCP

     my $in = slurp $infile;
     assert_eq $infile, $in, $out ;
  } ;
  ok $@ || '', '', 'diff' ;
},

sub {
  eval {
     my $out ;
     my $infile = "t/test-revml-in-0-no-big-files.revml";
     ## $in and $out allow us to avoid execing diff most of the time.
     run [ @vcp, "vcp:-" ], \<<'END_VCP', \$out;
Source: t/test-revml-in-0-no-big-files.revml

Sort:

Destination: -

Map:
    add/f(1)   hey/a$1b
    add/f(2)   hey/a${1}b
    add/f(*)   hey/a${1}b
END_VCP
     my $in = slurp $infile;

     $in =~ s{(<name>)add/f([^<]*)}{$1hey/a$2b}g;
     
     assert_eq $infile, $in, $out ;
  } ;
  ok $@ || '', '', 'diff' ;
},

) ;

plan tests => scalar( @tests ) ;

$_->() for @tests ;
