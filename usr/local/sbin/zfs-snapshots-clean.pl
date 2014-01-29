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
use 5.0010_001;
use feature qw/:5.10/;
BEGIN {
  use Carp;
  use POSIX qw/strftime/;
  use DateTime;
  use Getopt::Std;

  use constant {
    FALSE    => 0,
    TRUE     => 1,
    EX_OK    => 0,
    EX_ERROR => 1,
  };
  $| = 1;
  $, = "\n";
  $\ = "\n";
}

my $rc = EX_OK;
my $zfs = `which zfs`; chomp $zfs;
my $snapshots = {};
my $destroylist = ();
my $option = {};
getopt('d:',$option);

my $viability = DateTime::Duration->new( days => $option->{d} // 10);
my $today     = DateTime->now->truncate( to => 'day' );
my $cutoff    = $today->subtract_duration( $viability );

unless (   (-f $zfs)
        && (-x $zfs)) {
  say "Can not execute $zfs tool.";
  exit EX_ERROR;
}

open (FH, "$zfs list -H -t snapshot -o name |");
while (<FH>) {
  my $snap = $_; chomp $snap;
  my ($pool, $snapname, $snapdate) =
    ($snap =~ m/(.*?)@(.*):(\d{8})$/) or next;
  $snapshots->{$pool}->{$snapdate} = $snapname;
}
close FH;

for my $pkey ( sort keys %$snapshots ) {
  my $pool = $snapshots->{$pkey};

  $pool->{_daily}   = FALSE;
  $pool->{_weekly}  = FALSE;
  $pool->{_monthly} = FALSE;

  for my $dkey ( reverse sort keys %$pool ) {
    next if $_ =~ /^_/;

    my $discard = TRUE;
    my $snapname = $pool->{$dkey};

    my ($year, $month, $day) = ($dkey =~ m/(\d{4})(\d{2})(\d{2})/);
    my $snapdate = DateTime->new( year => $year, month => $month, day => $day);

    my $delta_t = $snapdate->subtract_datetime( $cutoff );
    $discard = FALSE if $delta_t->is_positive;

    # the latest Daily/Weekly/Monthly snapshots are always kept
    given ($snapname) {
      when (/Daily$/) {
        if ($pool->{_daily} == FALSE) {
          $discard = FALSE;
          $pool->{_daily} = TRUE;
        }
      }
      when (/Weekly$/) {
        if ($pool->{_weekly} == FALSE) {
          $discard = FALSE;
          $pool->{_weekly} = TRUE;
        }
      }
      when (/Monthly$/) {
        if ($pool->{_monthly} == FALSE) {
          $discard = FALSE;
          $pool->{_monthly} = TRUE;
        }
      }
    }
    if ($discard == TRUE) {
      push(@$destroylist,"${pkey}".'@'."${snapname}:${dkey}");
    }
  }
}
say "Destroying old snapshots:";
foreach (@$destroylist) {
  say "- $_";
  system($zfs,"destroy","-v",$_);
  my $ex = $? >> 8;
  # set $rc to the highest exit code we encounter
  $rc = ($ex == 0) ? $rc : ($ex > $rc) ? $ex : $rc;
}
exit $rc;
