#!/usr/bin/perl
#
# Assert that a courier-derived .dat file is actually usable, not merely present.
#
# Exit status from the make* tools is not sufficient. The failure mode that
# costs mail is a successfully-written database that is empty or truncated:
# makeuserdb pipes into makedat, and a source it cannot parse can still produce
# a valid GDBM file with nothing useful in it. courier then answers every
# lookup with "no such user" and mail bounces, with no error anywhere.
#
# So this opens the database the same way courier does -- courier-authlib's
# userdb2.c is a dbobj_open plus dbobj_fetch -- and checks what came out.
# GDBM_File ships with the perl that makeuserdb itself is written in, so this
# adds no dependency.
#
# Usage:
#   validate-courier-dat.pl --dat FILE [--expect-records N | --min-records N]
#                           [--canary KEY [--canary-match REGEX]]

use strict;
use warnings;
use GDBM_File;
use Getopt::Long;

my ($dat, $expect, $min, $canary, $match, $label);
GetOptions(
    "dat=s"            => \$dat,
    "expect-records=i" => \$expect,
    "min-records=i"    => \$min,
    "canary=s"         => \$canary,
    "canary-match=s"   => \$match,
    "label=s"          => \$label,
) or die "usage: $0 --dat FILE [--expect-records N|--min-records N] [--canary KEY [--canary-match RE]]\n";

die "$0: --dat is required\n" unless defined $dat;
$label ||= $dat;

my @fail;
sub fail { push @fail, $_[0] }

unless (-e $dat)      { print STDERR "FAIL $label: does not exist\n"; exit 1 }
unless (-s $dat)      { print STDERR "FAIL $label: is empty (0 bytes)\n"; exit 1 }

my %db;
unless (tie %db, 'GDBM_File', $dat, GDBM_READER, 0) {
    print STDERR "FAIL $label: not a readable GDBM database: $!\n";
    exit 1;
}

my $count = 0;
$count++ for keys %db;

if (defined $expect) {
    fail("expected exactly $expect records, found $count")
        if $count != $expect;
} elsif (defined $min) {
    fail("expected at least $min records, found $count")
        if $count < $min;
} else {
    # No count given: an empty database is still never right. Every derived
    # file here exists because something needs to be looked up in it.
    fail("database is structurally valid but contains no records")
        if $count == 0;
}

if (defined $canary) {
    my $value = $db{$canary};
    if (!defined $value) {
        fail("canary key '$canary' is absent (database has $count record(s))");
    } elsif (defined $match && $value !~ /$match/) {
        my $shown = length($value) > 120 ? substr($value, 0, 120) . "..." : $value;
        fail("canary '$canary' does not match /$match/: got '$shown'");
    }
}

untie %db;

if (@fail) {
    print STDERR "FAIL $label:\n";
    print STDERR "  - $_\n" for @fail;
    exit 1;
}

printf("ok   %-34s %d record(s)%s\n", $label, $count,
       defined $canary ? ", canary '$canary' resolves" : "");
exit 0;
