#!/usr/bin/env perl

#TODO Need to change to emit a build script which can be run on the FTP site 
#TODO and directory structure needs to change to 
#TODO pub/release-66/TYPE/species/fakegroup/symlink - for people just after data
#TODO pub/release-66/data_files/NORMALPATH/symlink - for people to mirror the 66 site

#TODO also use EnsEMBL::Web::Document::HTML::FTPtable required_types_for_species() && titles() 

package Script;

use strict;
use warnings;

use Bio::EnsEMBL::Registry;
use File::Find;
use File::Spec;
use File::Path qw/mkpath/;
use Getopt::Long qw/:config no_ignore_case auto_version bundling_override/;
use Pod::Usage;

my $rcsid = '$Revision$';
our ($VERSION) = $rcsid =~ /(\d+\.\d+)/;

sub run {
  my ($class) = @_;
  my $self = bless({}, $class);
  $self->args();
  $self->check();
  $self->setup();
  $self->process();
  return;
}

sub args {
  my ($self) = @_;
  my $opts = {
    port => 3306
  };
  GetOptions(
    $opts, qw/
      release|version=i
      dry
      host|hostname|h=s
      port|P=i
      username|user|u=s
      password|pass|p=s
      datafile_dir=s
      ftp_dir=s
      verbose 
      help
      man
      /
  ) or pod2usage(-verbose => 1, -exitval => 1);
  pod2usage(-verbose => 1, -exitval => 0) if $opts->{help};
  pod2usage(-verbose => 2, -exitval => 0) if $opts->{man};
  $self->{opts} = $opts;
  return;
}

sub opts {
  my ($self) = @_;
  return $self->{'opts'};
}

sub check {
  my ($self) = @_;
  my $o = $self->opts();

  my @required_params = qw/host username datafile_dir ftp_dir release/;

  foreach my $r (@required_params) {
    if (!$o->{$r}) {
      pod2usage(
        -message => "-${r} has not been given at the command line but is a required parameter",
        -verbose => 1,
        -exitval => 1
      );
    }
  }
  
  foreach my $key (qw/datafile_dir ftp_dir/) {
    my $dir = $o->{$key};
    if(! -d $dir) {
      pod2usage(
        -message => "-${key} given location '${dir}' does not exist",
        -verbose => 1,
        -exitval => 1
      );
    }
  }
  
  return;
}

sub setup {
  my ($self) = @_;
  my $o = $self->opts();
  
  $self->v('Using the database server %s@%s:%d', map { $o->{$_} } qw/username host port/);
  
  ##SETTING UP REGISTRY
  my %args = (
    -HOST => $o->{host}, -PORT => $o->{port}, 
    -USER => $o->{username}, -DB_VERSION => $o->{release},
  ); 
  $args{-PASS} = $o->{password} if $o->{password};
  my $loaded = Bio::EnsEMBL::Registry->load_registry_from_db(%args);
  $self->v('Loaded %d DBAdaptor(s)', $loaded);
  
  return;
}

sub process {
  my ($self) = @_;
  my $dbas = $self->_get_core_like_dbs();
  foreach my $dba (@$dbas) {
    $self->_process_dba($dba);
  }
  return;
}

sub _process_dba {
  my ($self, $dba) = @_;
  $self->v('Working with species %s', $dba->species());
  my $datafiles = $dba->get_DataFileAdaptor()->fetch_all();
  if(! @{$datafiles}) {
    $self->v("\tNo datafiles found");
  }
  else {
    foreach my $df (@{$datafiles}) {
      next if $df->absolute();
      $self->_process_datafile($df, $self->_target_species_root($df));
      $self->_process_datafile($df, $self->_target_datafiles_root($df));
    }
  }
  $dba->dbc()->disconnect_if_idle();
  return;
}

sub _process_datafile {
  my ($self, $datafile, $target_dir) = @_;
  if(! -d $target_dir) {
    if($self->opts->{dry}) {
      $self->v("\tWould have created directory '%s'", $target_dir);
    }
    else {
      $self->v("\tCreating directory '%s'", $target_dir);
      mkpath($target_dir) or die "Cannot create the directory $target_dir: $!";
    }
  }
  my $files = $self->_files($datafile);
  foreach my $filepath (@{$files}) {
    my ($file_volume, $file_dir, $name) = File::Spec->splitpath($filepath);
    my $target = File::Spec->catfile($target_dir, $name);
    if($self->opts()->{dry}) {
      $self->v("\tWould have linked '%s' -> '%s'", $filepath, $target);
    }
    else {
      if(-e $target) {
        if(-f $target) {
          my $id = $datafile->dbID();
          die "Cannot unlink $target as it is a file and not a symbolic link. Datafile ID was $id";
        }
        elsif(-h $target) {
          unlink $target;
        }
      }
      $self->v("\tLinking %s -> %s", $filepath, $target);
      symlink($filepath, $target) or die "Cannot symbolically link $filepath to $target: $!";
    }
  }
  return;
}

# Expected path: base/FILETYPE/SPECIES/TYPE/files
# e.g. pub/release-66/bam/pan_trogladytes/genebuild/chimp_1.bam
sub _target_species_root {
  my ($self, $datafile) = @_;
  my $base = $self->opts()->{ftp_dir};
  my $file_type = $self->_datafile_to_type($datafile); 
  my $ftp_type = $self->_dba_to_ftp_type($datafile->adaptor()->db());
  my $species = $datafile->adaptor()->db()->get_MetaContainer()->get_production_name();
  return File::Spec->catdir($base, $file_type, $species, $ftp_type);
}

# Expected path: base/data_files/normalpath
# e.g. pub/release-66/data_files/pan_trogladytes/CHIMP2.14/rnaseq/chimp_1.bam
sub _target_datafiles_root {
  my ($self, $datafile) = @_;
  my $base = File::Spec->catdir($self->opts()->{ftp_dir}, 'data-files');
  my $target_location = $datafile->path($base);
  my ($volume, $dir, $file) = File::Spec->splitpath($target_location);
  return $dir;
}

sub _datafile_to_type {
  my ($self, $datafile) = @_;
  return lc($datafile->file_type());
}

sub _dba_to_ftp_type {
  my ($self, $dba) = @_;
  my $group = $dba->group();
  my $type = {
    core => 'genebuild',
    rnaseq => 'genebuild',
    otherfeatures => 'genebuild',
    
    variation => 'variation',
    
    funcgen => 'funcgen',
  }->{$group};
  die "No way to convert from $group to a type" unless $type;
  return $type;
}

sub _get_core_like_dbs {
  my ($self) = @_;
  my $dbas = Bio::EnsEMBL::Registry->get_all_DBAdaptors();
  my @final_dbas;
  while(my $dba = shift @{$dbas}) {
    next if $dba->species() eq 'multi';
    next if lc($dba->species()) eq 'ancestral sequences';
    
    my $type = $dba->get_MetaContainer()->single_value_by_key('schema_type');
    $dba->dbc()->disconnect_if_idle();
    next unless $type;
    push(@final_dbas, $dba) if $type eq 'core';
  }
  $self->v('Found %d core like database(s)', scalar(@final_dbas));
  return \@final_dbas;
}

sub _files {
  my ($self, $datafile) = @_;
  my $source_file = $datafile->path($self->opts()->{datafile_dir});
  my ($volume, $dir, $name) = File::Spec->splitpath($source_file);
  my $regex = qr/^$name.*/;
  my @files;
  find(sub {
    push(@files, $File::Find::name) if $_ =~ $regex;
  }, $dir);
  return \@files;
}

sub v {
  my ($self, $msg, @params) = @_;
  return unless $self->opts()->{verbose};
  printf(STDERR $msg."\n", @params);
  return;
}

Script->run();

1;
__END__

=pod

=head1 NAME

build_datafile_ftp_directory.pl

=head1 SYNOPSIS

  #BASIC
  ./build_datafile_ftp_directory.pl -release VER -user USER -pass PASS -host HOST [-port PORT] -datafile_dir DIR -ftp_dir DIR [-dry] [-verbose] [-help | -man]
  
  #EXAMPLE dry
  ./build_datafile_ftp_directory.pl -release 66 -host ensembdb.ensembl.org -port 5306 -user anonymous -verbose -datafile_dir /my/datafile -ftp_dir /target/datafile/pub -dry
  
  #EXAMPLE do it
  ./build_datafile_ftp_directory.pl -release 66 -host ensembdb.ensembl.org -port 5306 -user anonymous -verbose -datafile_dir /my/datafile -ftp_dir /target/datafile/pub

=head1 DESCRIPTION

A script which will link all files for datafiles in a release into a
FTP compatible directory format.

=head1 OPTIONS

=over 8

=item B<--username | --user | -u>

REQUIRED. Username of the connecting account. Must be able to perform 
C<SELECT INTO OUTFILE> calls.

=item B<--password | -pass | -p>

REQUIRED. Password of the connecting user.

=item B<--release | --version>

REQUIRED. Indicates the release of Ensembl to process

=item B<--host | --host | -h>

REQUIRED. Host name of the database to connect to

=item B<--port | -P>

Optional integer of the database port. Defaults to 3306.

=item B<--datafile_dir>

  -datafile_dir /datafile/dir

REQUIRED. Source directory which is the intended root of the datafiles.

=item B<--ftp_dir>

  -ftp_dir /ftp/site/pub/release-66

REQUIRED. Target directory to symbolically link into. Push directly into the
release directory as the script does not assume the directory is publically
available.

=item B<--verbose>

Makes the program give more information about what is going on. Otherwise
the program is silent.

=item B<--dry>

If specified the script will inform of the types of commands and actions it 
would have performed.

=item B<--help>

Help message

=item B<--man>

Man page

=back

=head1 REQUIREMENTS

=over 8

=item Perl 5.8+

=item Bio::EnsEMBL

=item Post 66 databases

=back

=end
