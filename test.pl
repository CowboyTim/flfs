#!/usr/bin/perl -w
#
use strict; use warnings;


use Fcntl;
use Fcntl qw(SEEK_CUR);


my $mntpoint = $ARGV[0] or die "Usage: $0 <mountpount>\n";
my $file     = "$mntpoint/file";

sysopen(my $fh, $file, O_CREAT|O_TRUNC|O_RDWR)
    or die "Error opening $file: $!\n";

my $r = syswrite($fh, 'x' x 10, 4, 4);
if(!defined $r){
    die "Error syswrite: $!\n";
}

$r = syswrite($fh, 'x' x 10, 5, 4);
if(!defined $r){
    die "Error syswrite: $!\n";
}

sysseek($fh, 4097, SEEK_CUR) or die "Error seek: $!\n";
$r = syswrite($fh, 'x' x 10, 5, 4);
if(!defined $r){
    die "Error syswrite: $!\n";
}

$r = syswrite($fh, 'B' x 10_000_000, 10_000_000);
if(!defined $r){
    die "Error syswrite: $!\n";
}


close($fh) or die "Error closing $file: $!\n";
