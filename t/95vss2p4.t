#!/usr/local/bin/perl -w

=head1 NAME

p4.t - testing of vcp p4 i/o

=cut

use strict ;

use Carp ;
use File::Spec ;
use Test ;
use VCP::TestUtils ;

my $t = -d 't' ? 't/' : '' ;

my @vcp = ( vcp_cmd, "vcp:-" );

my $project = "revml2vss";

## Repositories to read from
my $vssroot_0 = "${t}vssroot_0";
my $vssroot_1 = "${t}vssroot_1";

my $vssspec_0 = "vss:Admin\@$vssroot_0:$project";
my $vssspec_1 = "vss:Admin\@$vssroot_1:$project";

## where to put the destination repository
my $destroot = tmpdir "destp4root";

my $state_location = tmpdir "vcp_state";

## where to write to in the destination repo
my $dest_spec = "p4:$destroot://depot/...";

my $repo_id;

sub _clean_up_in_and_out {
   my ( $in_ref, $out_ref ) = @_;

   s_content qw( rep_type ),        $in_ref,           "p4";
   s_content qw( user_id ),         $in_ref,           "Admin";
   rm_elts   qw( mod_time ),        $in_ref;
   rm_elts   qw( p4_info ),                  $out_ref;
   s_content qw( rev_root ),        $in_ref,           "depot";
   s_content qw( source_repo_id ),  $in_ref,           "p4:test_repository";
   s_content qw(
      rep_desc time rev_id source_rev_id change_id source_change_id
   ), $in_ref, $out_ref;
   $$in_ref =~ s{(id="|_id>)/+ignored}{$1//depot}g;

   rm_elts qw( placeholder ), $in_ref;
   rm_elts qw( comment ), qr{create_branches\r?\n}, $out_ref;

   rm_elts qw( change_id source_change_id ), $in_ref, $out_ref;
      ## vss has no change_ids

   rm_elts qw( comment ), qr/[^<]*\[vcp\][^<]*/, $out_ref;
      ## remove the "[vcp] using estimated..." comments

   rm_elts qw( user_id ), qr/unknown_vss_user/, $out_ref;

   ## VSS provides neither type nor time on deletions
   $$out_ref =~
       s{[ \t]*<type>[^<]*</type>\r?\n((?:(?!<rev[\s>]).)*<delete)}{$1}gs;

   $$out_ref =~
       s{[ \t]*<time>[^<]*</time>\r?\n((?:(?!<rev[\s>]).)*<delete)}{$1}gs;

   ## p4 is more parsimonious with its version numbers than vss
   $$in_ref  =~ s{#[0-9.]+("|<)}{#deleted by test suite$1}g;
   $$out_ref =~ s{#[0-9.]+("|<)}{#deleted by test suite$1}g;

}

my @tests = (
##
## vss->p4 bootstrap
##
## read p4root_0 into destroot
sub {
   my $vcp_spec = <<VCP_FILE;
Source:      $vssspec_0/...
               --repo-id=vss:test_repository

Destination: $dest_spec
               --init-p4d
               --delete-p4d-dir
               --db-dir=$state_location
               --repo-id=p4:dest_test_repository

VCP_FILE

   eval { run \@vcp, \$vcp_spec };
   ok $@ || '', '';
},

## read repository built in previous test, and compare it to the
## test-vss-in-0.revml to see how it compares to a file that hasn't been
## through a revml->vss->p4->revml pipeline.
sub {
   return skip "previous test failed", 1 if $@;

   my $infile  = $t . "test-vss-in-0.revml" ;
   my $in = slurp $infile ;
   my $out = get_vcp_output $dest_spec, "--run-p4d",
      "--repo-id=p4:test_repository",
      { revml_out_spec => [ "--db-dir=$state_location", "--repo-id=revml:test_repository" ] } ;

   _clean_up_in_and_out \$in, \$out;

   ok_or_diff $out, $in;
},

## --repo-id here should agree with the other one above that writes to
## the same destination.  because we are faking by reading from two
## different repositories that are really for test purposes snapshots
## of the same repository at two different moments in time.  
##
## because vcp would by default use the paths to these two
## repositories as the repo_ids, vcp would refuse to add an
## incremental export from the second repository on top of the
## revisions from the first repository.  by specifying the same
## repo_id in both places, we make vcp think that the revisions came
## from the same repository.

##
## vss->p4 incremental export
##
## read from vssroot_1 repository into p4.
##
sub {
   eval { run \@vcp, \<<VCP_END; } or die $@;
Source:      $vssspec_1/...
               --repo-id=vss:test_repository
               --continue

Destination: $dest_spec
               --run-p4d
               --db-dir=$state_location
               --repo-id=p4:dest_test_repository

VCP_END

   ok 1;
},


## extract stuff inserted into cvs in the previous test and compare
## to the source revml to see that it got there ok.
sub {
   my $infile  = $t . "test-vss-in-1.revml" ;
   my $in = slurp $infile ;
   my $out = get_vcp_output $dest_spec, "--continue", "--run-p4d",
      "--repo-id=p4:test_repository",
      { revml_out_spec => [ "--db-dir=$state_location", "--repo-id=revml:test_repository" ] } ;
   
   _clean_up_in_and_out \$in, \$out;

   ok_or_diff $out, $in;
},

);  # end @tests.


plan tests => scalar @tests;

my $p4d_borken = $ENV{P4BORKEN}  || p4d_borken ;


my $why_skip ;
$why_skip .= "p4 command not found"  unless ( `p4 -V`  || 0 ) =~ /^Perforce/ ;
$why_skip .= "p4 missing or broken"  if $p4d_borken ;
$why_skip .= "vss missing or broken" if vss_borken;

$why_skip ? skip( $why_skip, '' ) : $_->() for @tests ;
