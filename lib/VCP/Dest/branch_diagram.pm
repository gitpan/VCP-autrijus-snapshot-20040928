package VCP::Dest::branch_diagram ;

=head1 NAME

VCP::Dest::branch_diagram - An experimental diagram drawing "destination"

=head1 SYNOPSIS

   vcp <source> branch_diagram:foo.png
   vcp <source> branch_diagram:foo.png --skip=none ## for verbose output

=head1 DESCRIPTION

This generates (using GraphViz) a diagram of the branch structure of the
source repository.

Note: You must install graphviz, from AT&T (specifically, the C<dot> command)
and the GraphViz.pm Perl module for this to work.

=head1 OPTIONS

=over

=item --skip

  --skip=5

Set the revision "skip" threshold.  This is the minimum number of
revisions you should see in a "# skipped" message in the resulting
graph.  use C<--skip=none> to prevent skipping.  The default is 5.

=back

=head1 EXAMPLES

    vcp \
      p4:public.perforce.com:1666://public/perforce/webkeeper/mod_webkeep.c \
        --rev-root= \
        --follow-branch-into \
      branch_diagram:foo3.png

The --rev-root= is because the presumed rev root is
"//public/perforce/webkeeper" and perforce branches sail off in to other
directories.

    vcp \
      cvs:/home/barries/src/VCP/tmp/xfree:/xc/doc/Imakefile \
      branch_diagram:foo3.png

=cut

$VERSION = 1 ;

@ISA = qw( VCP::Dest );

use strict ;

use Carp ;
use File::Basename ;
use File::Path ;
use File::Spec ;
use VCP::Debug ':debug' ;
use VCP::Dest ;
use VCP::Logger qw( pr );
use VCP::Rev ;
use VCP::Revs ;
use VCP::Utils qw( empty start_dir_rel2abs );

#use base qw( VCP::Dest ) ;
#use fields (
#   'BD_SKIP_THRESHOLD',    ## Where to start skipping.
#   'BD_BRANCH_COLORS',     ## A hash of branch_id to color
#   'BD_REV_FOO',           ## Data we need to keep per rev
#   'BD_REVS',              ## a HASH of Revs, keyed by id
#   'BD_BRANCH_IDS',        ## A HASH of branch_ids so we can assign colors
#) ;

#=item new
#
#Creates a new instance of a VCP::Dest::branch_diagram.
#
#=cut

sub new {
   my $self = shift->SUPER::new( @_ ) ;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $self->parse_repo_spec( $spec ) if defined $spec;

   $self->parse_options( $options );

   return $self ;
}

sub options_spec {
   my $self = shift ;
   return (
      $self->SUPER::options_spec,
      "skip=s" => \$self->{BD_SKIP_THRESHOLD},
   );
}

sub init {
   my $self = shift ;

   $self->{BD_BRANCH_COLORS} = {};
   $self->{BD_REV_FOO} = {};

   $self->{BD_SKIP_THRESHOLD} = 5 unless defined $self->{BD_SKIP_THRESHOLD};
   $self->repo_id( "branch_diagram:" . ( $self->repo_server || "" ) );
}


sub backfill {
   my $self = shift ;
   my $r ;
   ( $r ) = @_ ;

confess unless defined $self && defined $self->header ;

   return 1 ;
}


sub handle_header {
   my $self = shift ;
   $self->SUPER::handle_header( @_ ) ;
}


sub handle_rev {
   my $self = shift ;
   my ( $r ) = @_;

   $self->{BD_REVS}->{$r->id} = $r;

   $self->{BD_BRANCH_IDS}->{$r->branch_id || "" } = undef;

   $self->{BD_REV_FOO}->{$r->previous_id}->{COUNT}++
      if defined $r->previous_id;
}


sub _add_rev_node {
   my $self = shift ;
   my ( $g, $r ) = @_;

   my $action = $r->action || "";

   my $label = join( "",
      $r->rev_id,
      defined $r->change_id
         ? ( "@", $r->change_id )
         : (),
      $r->is_placeholder_rev
         ? "(placeholder)"
      : $r->is_base_rev
         ? "(base rev)"
      : ( "(", $r->action, ")" ),
   );
   $label =~ s#([|<>\[\]{}"])#\\$1#g;

   {
      my @labels = $r->labels;
      @labels = ( @labels[0,1,2], "...", @labels[-3,-2,-1] )
         if @labels > 7;
      $label = "{$label|{"
         . join( "",
            map {
               $_ =~ s#([|<>\[\]{}"])#\\$1#g; $_ . "\\l"
            } @labels
          ) . "}}"
          if @labels;
   }

   my @color;
   my @edge_fontcolor;
   my @bgcolor;
   ## NOTE: this version of GraphViz seems to accept but ignore the
   ## "fillcolor" attribute.
   if ( ! empty $r->branch_id ) {
      my $color = $self->{BD_BRANCH_COLORS}->{$r->branch_id};
      @color          = (                    color     => $color );
      @edge_fontcolor = (                    fontcolor => $color );
#      @bgcolor        = ( style => "filled", color     => $color );
      @bgcolor        = ( style => "filled", fillcolor => $color );
      @bgcolor        = ();
   }

   my $group = join "", $r->name, "(", $r->branch_id || "", ")";

   $g->add_node(
      $r->id,
      label    => $label,
      cluster  => $r->name,
      fontsize => 10,
      fontname => "Helvetica",
      shape    => "record",
      height   => 0,
      width    => 0,
      group    => $group,
      color    => "black",
      @bgcolor,
   );

   my $prev_r = $self->{BD_REV_FOO}->{$r->id}->{PREVIOUS};
   $prev_r = $self->{BD_REVS}->{$r->previous_id}
      unless defined $prev_r || empty $r->previous_id;
   return unless $prev_r;

   my $branch_id = $r->branch_id || "";

   my $is_new_branch = $prev_r &&
       $branch_id ne ( $prev_r->branch_id || "" );

   my $branch_label = "";
   $branch_label = $branch_id if $is_new_branch;

   if ( $prev_r ) {
      my $prev_id = $prev_r->id;

      my $skipped = $self->{BD_REV_FOO}->{$r->id}->{SKIPPED};

      if ( $skipped ) {
         my $k = "..." . $r->id;
         $g->add_node(
            $k,
            label => "$skipped skipped",
            cluster  => $r->name,
            fontsize => 10,
            fontname => "Helvetica",
            shape    => "record",
            height   => 0,
            width    => 0,
            peripheries => 0,
            group    => $group,
            @edge_fontcolor,
         );

         $g->add_edge( {
            label    => $branch_label,
            from     => $prev_id,
            to       => $k,
            fontsize => 10,
            fontname => "Helvetica",
            @color,
            @edge_fontcolor,
            arrowhead => "none",
            length $branch_label
               ? ( weight => 0 )
               : (),
         } );

         $prev_id = $k,
         $branch_label = "";
      }

      $g->add_edge( {
         label    => $branch_label,
         fontsize => 10,
         fontname => "Helvetica",
         from     => $prev_id,
         to       => $r->id,
         @edge_fontcolor,
         @color,
         length $branch_label
            ? ( weight => 0 )
            : (),
      } );
   }
}


sub handle_footer {
   my $self = shift ;

   my $fn = $self->repo_filespec;

   $fn = start_dir_rel2abs $fn ;

   my ( $ext ) = ( $fn =~ /\.([^.]*)\z/ );
   my $method = "as_$ext";

   pr "Generating branch diagram in ", $fn;

   my %seen_colors;
   my $total;
   my $count;

   my @colors =
      map $_->[-1],
      reverse sort { $a->[0] <=> $b->[0] }
      grep {
         my $avg = $_->[0];
         $total += $avg;
         ++$count;
         (  $_->[-1] =~ /gray/ ? $avg > 125 : $avg > 100 )
         && $avg < 160
      }
      map [ ( $_->[0] + $_->[1] + $_->[2] ) / 3, @$_],
      grep $_->[-1] =~ /\A[a-z\s]+\z/,
      grep !$seen_colors{$_->[-1]}++,
      map { $_->[-1] =~ s/grey/gray/g; $_ }
      map [ split /\s+/, $_, 4 ],
      split /\n+\s*/, `showrgb`;

#use Slay::PerlUtil; dump \@colors;
#die;

   for ( keys %{$self->{BD_BRANCH_IDS}} ) {
       my $c = shift @colors;
       @colors = ( @colors, $c );
       $self->{BD_BRANCH_COLORS}->{$_->branch_id} = $c;
   }

#use Slay::PerlUtil; dump \%branch_colors;

   my %names;

   my $foo = $self->{BD_REV_FOO};

   $foo->{$_->id}->{VIS} = 1 for
      grep {
         my $f = $foo->{$_->id};
         ( $f->{COUNT} || 0 ) != 1
           || empty( $_->previous_id )
           || $_->labels;
      }
      values %{$self->{BD_REVS}};

   for my $r ( values %{$self->{BD_REVS}} ) {
      $names{$r->name} = 1;
      next unless $foo->{$r->id}->{VIS};

      if ( ! empty( $r->previous_id ) ) {
         my $prev_r = $self->{BD_REVS}->{$r->previous_id};
         my @skipped;
         while ( ! $foo->{$prev_r->id}->{VIS}
            && ! empty( $prev_r->previous_id )
         ) {
            push @skipped, $prev_r;
            $prev_r = $self->{BD_REVS}->{$prev_r->previous_id};
         }

         ## Only skip enough to matter
         if ( $self->{BD_SKIP_THRESHOLD} ne "none" 
            && @skipped >= $self->{BD_SKIP_THRESHOLD}
         ) {
            $foo->{$r->id}->{SKIPPED} = @skipped;
            $foo->{$r->id}->{PREVIOUS} = $prev_r;
         }
         else {
            $foo->{$_->id}->{VIS} = 1 for @skipped;
         }
      }
   }

   ## Load lazily so options parsing can be tested.
   require GraphViz;
   my $g = GraphViz->new(
#      rankdir => "LR",  ## Wide .pngs can't be created, go tall.
      nodesep  => 0.1,
      ranksep  => 0.25,
      ordering => "out",
      keys %names <= 1
         ? ( label => scalar keys %names )
         : ()
   );

   ## Sort by name to get predictable ordering of files from left to right
   ## Sort by branch ID to put all branches to right (because
   ## ordering => "out" set on the graph)
   for my $r ( sort {
      $a->name cmp $b->name
      || ( $a->branch_id || "" ) cmp ( $b->branch_id || "" )
      } values %{$self->{BD_REVS}}
   ) {
      next unless $foo->{$r->id}->{VIS};
      $self->_add_rev_node( $g, $r );
   }

   if ( $method eq "as_debug" ) {
      open  F, ">$fn" or die "$!: $fn";
      print F $g->_as_debug( $fn ) or die "$!: writing $fn";
      close F or die "$!: $fn";
   }
   else {
      $g->$method( $fn );
   }
}


=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
