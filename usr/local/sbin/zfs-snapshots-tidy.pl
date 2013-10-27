#!/usr/bin/perl
#
# Copyright (c) 2013  1&1 Internet AG
# Written by          Joerg Pernfuss <joerg.pernfuss@1und1.de>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
use strict;
use warnings;
use feature qw/:5.10/;
BEGIN {
  use Net::FTP::Common;
  use Data::Dumper;
  use Carp;
  use POSIX qw/strftime/;
  use DateTime;
  use Getopt::Std;
  use subs qw/mark_referenced/;

  use constant {
    OK    => 0,
    FALSE => 0,
    TRUE  => 1,
    ERROR => 1,
  };
  $| = 1;
  $, = "\n";
  $\ = "\n";
}

my $option = {};
getopt('d:', $option);
my $config = {
  always_keep_first => TRUE,
  validity => $option->{d} // 10,
};

our %netftp_config = (
  Debug   => 0,
  Timeout => 120
);

our %ftp_common_cfg = (
  User      => '',
  Pass      => '',
  Host      => '',
  LocalDir  => '/tmp',
  RemoteDir => '/',
  Type      => 'A',
);
my $backups = {};
my @newlist = ();
my @deletelist = ();

# get list of files from ftp directory
my $ez = Net::FTP::Common->new(\%ftp_common_cfg, %netftp_config);
$ez->login or croak "cant login: $@";
my @listing = $ez->ls;
$ez->quit;

# remove par2 files from list
foreach (@listing) {
  chomp;
  if ($_ !~ m/\.par2$/) {
    push(@newlist, $_);
  }
  else {
  }
}

# setup %$backups datastructure
foreach (@newlist) {
  $_ =~ m/^([[:alnum:]_]+)_([[:digit:]]{4,}[01][[:digit:]][012][[:digit:]])-([[:digit:]]{4,}[01][[:digit:]][012][[:digit:]])_([A-z]{4})\.tar$/;
  $backups->{$1}->{$3}->{_file}      = $_;
  $backups->{$1}->{$3}->{_type}      = $4;
  $backups->{$1}->{$3}->{_from}      = $2;
  $backups->{$1}->{$3}->{_to}        = $3;
  $backups->{$1}->{$3}->{_dataset}   = $1;
  $backups->{$1}->{$3}->{desired}    = FALSE;
  $backups->{$1}->{$3}->{referenced} = FALSE;
  $backups->{$1}->{$3}->{count}++;
}

# keep the last backup (and its dependencies), regardless of age
my $keep_last = ($config->{always_keep_first} == TRUE) ? TRUE : FALSE;

# identify backups that are still fresh
for my $key ( sort keys %$backups ) {
  my $dataset = $backups->{$key};
  for my $datekey ( reverse sort keys %$dataset ) {
    my ($year, $month, $day) = ($datekey =~ m/(\d{4})(\d{2})(\d{2})/);
    my $today = DateTime->now->truncate( to => 'day' );
    my $backupdate = DateTime->new( year => $year, month => $month, day => $day );
    my $validity = DateTime::Duration->new( days => $config->{validity} );

    my $cutoff = $today->subtract_duration( $validity );
    my $delta = $backupdate->subtract_datetime( $cutoff );

    if (   ( $delta->is_positive )
        || ( $keep_last == TRUE  )) {
      $keep_last = ($keep_last == TRUE) ? FALSE : $keep_last;
      my $backup = $dataset->{$datekey};
      $backup->{desired} = TRUE;

      mark_referenced( $backup->{_dataset}, $backup->{_from} );
    }
  }
}

# identify file that can be safely deleted
for my $key ( sort keys %$backups ) {
  my $dataset = $backups->{$key};
  for my $datekey ( reverse sort keys %$dataset ) {
    my $backup = $dataset->{$datekey};

    if (   ( $backup->{desired}    == FALSE )
        && ( $backup->{referenced} == FALSE )) {
      push (@deletelist, $backup->{_file});
    }
  }
}

# delete stale backups
say "Deleting old backup files from FTP:";
$ez->login or die "can't login $@";
$ez->ls;
foreach (@deletelist) {
  my $file = $_;

  $ez->delete( RemoteFile => $file );
  say "- $file";
  my @par2 = $ez->grep(Grep => qr/$file\..*/);
  foreach my $pf (@par2) {
    $ez->delete( RemoteFile => $pf );
    say "- $pf";
  }
}
$ez->quit;
exit OK;

# recurse through dependencies
sub mark_referenced {
  my ($dataset, $date) = @_;

  return unless (   defined $backups->{$dataset}
                 && defined $backups->{$dataset}->{$date});

  my $to   = $backups->{$dataset}->{$date}->{_to};
  my $from = $backups->{$dataset}->{$date}->{_from};

  $backups->{$dataset}->{$date}->{referenced} = 1;

  unless ( $to eq $from ) {
    mark_referenced( $dataset, $from );
  }

  return;
}
