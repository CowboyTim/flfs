#!/usr/bin/python

import sys
import shutil
import os
import getopt
import time
from stat import ST_SIZE

__doc__ = """
Usage: cp [options] src [src] dst
"""

def usage():
    """
    Print the usage, an error message, then exit with an error
    """
    print(globals()['__doc__'])
    sys.exit(1)


def main():
    try:
        opts, arg = getopt.getopt(sys.argv[1:], "ho:vo", ["help"])
    except getopt.GetoptError, err:
        print str(err) # will print something like "option -a not recognized"
        usage()

    verbose = False
    for o, a in opts:
        if o == "-v":
            verbose = True
        elif o in ("-h", "--help"):
            usage()
        else:
            assert False, "unhandled option"

    if len(arg) == 0:
        usage()
    first_arg = arg[0]
    last_arg  = arg[-1]
    
    if first_arg == last_arg:
        usage()

    target_is_dir = os.path.isdir(last_arg)
    if len(arg[0:-1]) > 1:
        if not target_is_dir:
            usage()

    try:
        dst = last_arg
        for src in arg[0:-1]:
            if target_is_dir:
                dst = dst+"/"+os.path.basename(src)
            if verbose:
                s = time.time()
                size = os.stat(src)[ST_SIZE]
                print("`"+src+"' -> `"+dst+"'")
                print(s)
            #shutil.copyfile(src, dst)
            fsrc = None
            fdst = None
            try:
                fsrc = open(src, 'rb')
                fdst = open(dst, 'wb')
                shutil.copyfileobj(fsrc, fdst, length=32*1024*1024)
            finally:
                if fdst:
                    fdst.close()
                if fsrc:
                    fsrc.close()
            shutil.copystat(src, dst)
            if verbose:
                e = time.time()
                print(e)
                print("%(#) 4.2f MiB/s" % { '#':size/(1024*1024*(e - s)) })
    except KeyboardInterrupt:
        sys.exit(130)
    except:
        raise

if __name__ == "__main__":
    main()

