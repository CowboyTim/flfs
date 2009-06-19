# makefile for fuse library for Lua

# change these to reflect your Lua installation
LUAINC= /usr/include/lua5.1
LUALIB= $(LUA)/lib
LUABIN= $(LUA)/bin

MYNAME= fuse

# no need to change anything below here except if your gcc/glibc is not
# standard
CFLAGS= $(INCS) $(DEFS) $(WARN) -O2 $G -D_FILE_OFFSET_BITS=64 -D_REENTRANT -DFUSE_USE_VERSION=26 -DHAVE_SETXATTR -fPIC
WARN= #-ansi -pedantic -Wall
INCS= -I$(LUAINC) -I$(MD5INC)
LIBS= -lfuse -llua5.1

OBJS = fuse.so

CC=gcc

all:    $(OBJS)

%.so:	%.c
	$(CC) -o $@ -shared $(CFLAGS) $(WARN) $(LIBS) $<
	strip $@

clean:
	rm -f $(OBJS)

