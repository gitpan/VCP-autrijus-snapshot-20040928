package VCP::Source::null ;

=head1 NAME

VCP::Source::null - A null source, for testing purposes

=head1 SYNOPSIS

   vcp null:

=head1 DESCRIPTION

Takes no options, delivers no data.

=cut

$VERSION = 1.0 ;

@ISA = qw( VCP::Source );

use strict ;

use Carp ;
use File::Spec;
use File::Temp;
use VCP::Debug ":debug" ;
use VCP::Source;
use VCP::Utils qw( is_win32 );

#use base qw( VCP::Source );

sub new {
   my $self = shift->SUPER::new;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   die "vcp: the null source takes no spec ('$1')\n"
      if defined $spec && $spec =~ m{\Anull:(.+)}i;

   $self->repo_id( "null" );

   $self->parse_repo_spec( $spec ) if defined $spec;
   $self->parse_options( $options );

   return $self ;
}


sub options_spec {
   return ();
}


sub handle_header {
   my $self = shift ;
   my ( $header ) = @_ ;

   $self->dest->handle_header( $header );
   return ;
}


my $null_fn;

sub get_source_file {
   my $self = shift;
   my ( $r ) = @_;

   if ( !defined $null_fn ) {
       ## On Win32, "NUL" is not a file like '/dev/null' is on Unix,
       ## so you can't link() to it.  Also, we need to be on the same
       ## file system as the other temp files for link()'s sake.
       my $fh;
       ( $fh, $null_fn ) = File::Temp::tempfile(
           "vcp_empty_file_XXXX",
           UNLINK => 1
       );
       close $fh;
           ## close it so files link()ed to this one may be unlink()ed
           ## on Win32
   }

   return $null_fn;
}


=head1 SEE ALSO

L<VCP::Dest::null>, L<vcp>.

=head1 AUTHOR

Barrie Slaymaker <barries@slaysys.com>

=head1 COPYRIGHT

Copyright (c) 2000, 2001, 2002 Perforce Software, Inc.
All rights reserved.

See L<VCP::License|VCP::License> (C<vcp help license>) for the terms of use.

=cut

1
