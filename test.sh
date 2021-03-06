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
        echo "***ERROR***"
        #fusermount -u $mntpoint
        exit 1
    fi
    ok=0
}

mkdir -p $mntpoint
trap my_err ERR INT TERM HUP
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

touch $mntpoint/aaf
mv $mntpoint/aaf $mntpoint/uui
mv $mntpoint/uui $mntpoint/tt/ll/kk/

touch $mntpoint/tt/pp/ooo
mkdir $mntpoint/yy
mv $mntpoint/tt/pp/ooo $mntpoint/yy
mv $mntpoint/yy/ooo $mntpoint/yy/uuu

ln $mntpoint/yy/uuu $mntpoint/yy/nnn
a=`ls -m $mntpoint/yy`
if [ "$a" != "nnn, uuu" ]; then
    echo "ERROR:$a"
    exit 1
fi
ln $mntpoint/yy/nnn $mntpoint/yy/mmm
a=`ls -m $mntpoint/yy`
if [ "$a" != "mmm, nnn, uuu" ]; then
    echo "ERROR:$a"
    exit 1
fi

ln -s $mntpoint/yy $mntpoint/newyy
a=`ls -m $mntpoint`
if [ "$a" != "newyy, tt, yy" ]; then
    echo "ERROR:$a"
    exit 1
fi

a=`readlink $mntpoint/newyy`
if [ "$a" != "$mntpoint/yy" ]; then
    echo "ERROR:$a"
    exit 1
fi
mv $mntpoint/newyy $mntpoint/newnewyy

mv $mntpoint/yy/nnn $mntpoint/yy/lll
mv $mntpoint/yy/lll $mntpoint/lll
a=`ls -l $mntpoint/lll|awk '{print $2}'`
if [ "$a" != '3' ]; then
    echo "ERROR:$a"
    exit 1
fi

rm -f $mntpoint/lll
sleep 1
a=`ls -l $mntpoint/yy/mmm|awk '{print $2}'`
if [ "$a" != '2' ]; then
    echo "ERROR:$a"
    exit 1
fi

rm -f $mntpoint/yy/mmm
mv $mntpoint/yy/uuu $mntpoint/tt/ll
mv $mntpoint/tt/ll/uuu $mntpoint/yy

mv $mntpoint/yy/uuu $mntpoint/tt/ll/kkk
a=`ls -l $mntpoint/tt/ll/kkk|awk '{print $2}'`
if [ "$a" != '1' ]; then
    echo "ERROR:$a"
    exit 1
fi
rm -f $mntpoint/tt/ll/kkk

mkfifo $mntpoint/pipe
a=`ls -l $mntpoint/pipe|awk '{print $1}'`
if [ "$a" != 'prw-r--r--' ]; then
    echo "ERROR:$a"
    exit 1
fi


    
mkdir -p /tmp/yyy/uuu/iui/d/d/d/d/d/d/d/d/d/d/d/d/d/d/d/d/d/d/d/d

#fusermount -u $mntpoint
