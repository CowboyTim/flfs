#!/bin/bash

here=`pwd`
mntpoint=$1
if [ -z $mntpoint ]; then
    echo "usage: $0 <mountpoint>"
    exit 0
fi


ok=0
function my_err (){
    if [ $ok == 0 ]; then
        cd $here
        fusermount -u $mntpoint
        exit 1
    fi
    ok=0
}

trap my_err ERR INT TERM HUP

mkdir -p $mntpoint
eval `fusermount -u $mntpoint`
(lua ./luafs.lua test $mntpoint -f)&

sleep 1

mkdir $mntpoint/tt
mkdir $mntpoint/tt/yy
mkdir $mntpoint/tt/yy/uu
rmdir $mntpoint/tt/yy/uu
rmdir $mntpoint/tt/yy
rmdir $mntpoint/tt

a=`ls $mntpoint`
if [ ! -z $a ]; then
    exit 1
fi

eval `mkdir $mntpoint/tt/yy/uu   || ok=1`
mkdir $mntpoint/tt
mkdir $mntpoint/tt/yy
eval `rmdir $mntpoint/tt         || ok=1`

chown tim $mntpoint/tt/yy
chmod -rwx $mntpoint/tt/yy

mv $mntpoint/tt $mntpoint/newtt

a=`ls $mntpoint`
if [ "$a" != 'newtt' ]; then
    echo "ERROR:$a"
    exit 1
fi

eval `chown tim $mntpoint/tt/yy  || ok=1`
eval `chmod -rwx $mntpoint/tt/yy || ok=1`

chown tim $mntpoint/newtt/yy
chmod -rwx $mntpoint/newtt/yy

eval `rmdir $mntpoint/newtt      || ok=1`
eval `rmdir $mntpoint/newtt/.    || ok=1`
eval `rmdir $mntpoint/newtt/yy/..|| ok=1`

rmdir $mntpoint/newtt/yy
rmdir $mntpoint/newtt

eval `ls $mntpoint/aaaa/aaaa     || ok=1`

mkdir $mntpoint/tt
ls $mntpoint//tt//
mkdir $mntpoint/tt/yy
a=`ls $mntpoint/tt`
if [ "$a" != 'yy' ]; then
    echo "ERROR:$a"
    exit 1
fi

a=`ls $mntpoint`
if [ "$a" != 'tt' ]; then
    echo "ERROR:$a"
    exit 1
fi

mkdir $mntpoint/tt/uu
mkdir $mntpoint/tt/pp
a=`ls -m $mntpoint/tt`
if [ "$a" != "pp, uu, yy" ]; then
    echo "ERROR:$a"
    exit 1
fi

cd $mntpoint/tt
a=`ls -m`
if [ "$a" != "pp, uu, yy" ]; then
    echo "ERROR:$a"
    exit 1
fi
mv uu ll
a=`ls -m`
if [ "$a" != "ll, pp, yy" ]; then
    echo "ERROR:$a"
    exit 1
fi
mkdir ll/kk
rmdir yy
cd $here


fusermount -u $mntpoint
