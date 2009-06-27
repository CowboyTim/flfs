#!/usr/bin/perl -w
#
use strict; use warnings;


use Fcntl;
use Fcntl qw(SEEK_CUR SEEK_SET);


my $mntpoint = $ARGV[0] or die "Usage: $0 <mountpount>\n";
my $file     = "$mntpoint/file";

my $fh;
my $r;

sysopen($fh, $file, O_CREAT|O_TRUNC|O_RDWR)
    or die "Error opening $file: $!\n";

$r = syswrite($fh, 'x' x 10, 4, 4);
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

$r = truncate($fh, 10);
if(!defined $r){
    die "Error truncate: $!\n";
}

$file = "$mntpoint/file2";

sysopen($fh, $file, O_CREAT|O_RDWR)
    or die "Error opening $file: $!\n";

$r = syswrite($fh, 'x' x 4096, 4096, 0);
if(!defined $r){
    die "Error syswrite: $!\n";
}
$r = syswrite($fh, 'y' x 4096, 4096, 0);
if(!defined $r){
    die "Error syswrite: $!\n";
}
close($fh) or die "Error closing $file: $!\n";

sysopen($fh, $file, O_APPEND|O_RDWR)
    or die "Error opening $file: $!\n";

$r = syswrite($fh, 'z' x 4096, 4096, 0);
if(!defined $r){
    die "Error syswrite: $!\n";
}


my $file1 = "$mntpoint/file1.".time();
sysopen(my $fh1, $file1, O_TRUNC|O_RDWR|O_CREAT)
    or die "Error opening $file1: $!\n";
my $file2 = "$mntpoint/file2.".time();
sysopen(my $fh2, $file2, O_TRUNC|O_RDWR|O_CREAT)
    or die "Error opening $file2: $!\n";

$r = syswrite($fh1, 'x' x (32*4096), 32*4096, 0);
if(!defined $r){
    die "Error syswrite: $!\n";
}

$r = syswrite($fh2, 'x' x (32*4096), 32*4096, 0);
if(!defined $r){
    die "Error syswrite: $!\n";
}

$r = syswrite($fh1, 'y' x (32*4096), 32*4096, 0);
if(!defined $r){
    die "Error syswrite: $!\n";
}

$r = syswrite($fh2, 'z' x (32*4096), 32*4096, 0);
if(!defined $r){
    die "Error syswrite: $!\n";
}

# close + reopen, perl/fuse/linux caches?
close($fh1) or die "Error closing $file1: $!\n";
close($fh2) or die "Error closing $file2: $!\n";
sysopen($fh1, $file1, O_RDWR) or die "Error opening $file1: $!\n";
sysopen($fh2, $file2, O_RDWR) or die "Error opening $file2: $!\n";

{
    sysseek($fh1, 4100, SEEK_SET)
        or die "Error seek: $!\n";
    my $s = sysread($fh1, my $a, 10_000, 0);
    if(!defined $s){
        die "Error sysread:$!\n";
    }
    print("size:".length($a)."\n");
    if( ('x' x 10_000) eq $a ){
        print("OK\n");
    }
}

{
    sysseek($fh2, 0, SEEK_SET)
        or die "Error seek: $!\n";
    my $s = sysread($fh2, my $a, 64*4096, 0);
    if(!defined $s){
        die "Error sysread:$!\n";
    }
    print("size:".length($a)."\n");
    if( ('x' x (32*4096)).('z' x (32*4096)) eq $a ){
        print("OK\n");
    }
}

close($fh1) or die "Error closing $file1: $!\n";
close($fh2) or die "Error closing $file2: $!\n";
