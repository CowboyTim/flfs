#!/usr/bin/perl -w
#
use strict; use warnings;
use Benchmark;

timethese(100,{
    "/tmp" => sub {
        my $i = 0;
        while($i < 1000){
            open(my $fh, ">", "/tmp/$i");
            close($fh);
            unlink("/tmp/$i");
            $i++;
        }
    },
    "/tmp/yyy" => sub {
        my $i = 0;
        while($i < 1000){
            open(my $fh, ">", "/tmp/yyy/$i");
            close($fh);
            unlink("/tmp/yyy/$i");
            $i++;
        }
    }
});
