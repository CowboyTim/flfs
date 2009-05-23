#!/usr/bin/env lua

local fuse = require 'fuse'
local lfs  = require "lfs"

list = require 'list'        -- must be global for loadstring()!

local S_WID     = 1 --world
local S_GID     = 2^3 --group
local S_UID     = 2^6 --owner
local S_SID     = 2^9 --sticky bits etc.
local S_IFIFO   = 1*2^12
local S_IFCHR   = 2*2^12
local S_IFDIR   = 4*2^12
local S_IFBLK   = 6*2^12
local S_IFREG   = 2^15
local S_IFLNK   = S_IFREG + S_IFCHR

-- for access(), taken from unistd.h
local R_OK      = 1 -- Test for read permissions
local W_OK      = 2 -- Test for write permissions
local X_OK      = 3 -- Test for execute permissions
local F_OK      = 4 -- Test for existence

local EPERM        = -1
local ENOENT       = -2
local EEXIST       = -17
local EINVAL       = -22
local EFBIG        = -27
local ENAMETOOLONG = -36
local ENOSYS       = -38
local ENOATTR      = -516
local ENOTSUPP     = -524

local BLOCKSIZE    = 4096
local STRIDE       = 64
local MAXINT       = 2^32 -1

--
-- shortcuts, lua speedups in fact
--
local substr    = string.sub
local floor     = math.floor
local time      = os.time
local join      = table.concat
local push      = table.insert
push            = table.insert  -- must be global for loadstring()!
local pop       = table.remove
local sort      = table.sort
local format    = string.format
local split     = string.gmatch
local match     = string.match

local function shift(t)
    return pop(t,1)
end

local function pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do 
        push(a, n) 
    end
    sort(a, f)
    local i = 0      -- iterator variable
    local iter = function ()   -- iterator function
        i = i + 1
        if a[i] == nil then return nil
        else return a[i], t[a[i]]
        end
    end
    return iter
end


--
-- Helper functions
--
local tab = {  -- tab[i+1][j+1] = xor(i, j) where i,j in (0-15)
  {0  , 1  , 2  , 3  , 4  , 5  , 6  , 7  , 8  , 9  , 10 , 11 , 12 , 13 , 14 , 15 , } , 
  {1  , 0  , 3  , 2  , 5  , 4  , 7  , 6  , 9  , 8  , 11 , 10 , 13 , 12 , 15 , 14 , } , 
  {2  , 3  , 0  , 1  , 6  , 7  , 4  , 5  , 10 , 11 , 8  , 9  , 14 , 15 , 12 , 13 , } , 
  {3  , 2  , 1  , 0  , 7  , 6  , 5  , 4  , 11 , 10 , 9  , 8  , 15 , 14 , 13 , 12 , } , 
  {4  , 5  , 6  , 7  , 0  , 1  , 2  , 3  , 12 , 13 , 14 , 15 , 8  , 9  , 10 , 11 , } , 
  {5  , 4  , 7  , 6  , 1  , 0  , 3  , 2  , 13 , 12 , 15 , 14 , 9  , 8  , 11 , 10 , } , 
  {6  , 7  , 4  , 5  , 2  , 3  , 0  , 1  , 14 , 15 , 12 , 13 , 10 , 11 , 8  , 9  , } , 
  {7  , 6  , 5  , 4  , 3  , 2  , 1  , 0  , 15 , 14 , 13 , 12 , 11 , 10 , 9  , 8  , } , 
  {8  , 9  , 10 , 11 , 12 , 13 , 14 , 15 , 0  , 1  , 2  , 3  , 4  , 5  , 6  , 7  , } , 
  {9  , 8  , 11 , 10 , 13 , 12 , 15 , 14 , 1  , 0  , 3  , 2  , 5  , 4  , 7  , 6  , } , 
  {10 , 11 , 8  , 9  , 14 , 15 , 12 , 13 , 2  , 3  , 0  , 1  , 6  , 7  , 4  , 5  , } , 
  {11 , 10 , 9  , 8  , 15 , 14 , 13 , 12 , 3  , 2  , 1  , 0  , 7  , 6  , 5  , 4  , } , 
  {12 , 13 , 14 , 15 , 8  , 9  , 10 , 11 , 4  , 5  , 6  , 7  , 0  , 1  , 2  , 3  , } , 
  {13 , 12 , 15 , 14 , 9  , 8  , 11 , 10 , 5  , 4  , 7  , 6  , 1  , 0  , 3  , 2  , } , 
  {14 , 15 , 12 , 13 , 10 , 11 , 8  , 9  , 6  , 7  , 4  , 5  , 2  , 3  , 0  , 1  , } , 
  {15 , 14 , 13 , 12 , 11 , 10 , 9  , 8  , 7  , 6  , 5  , 4  , 3  , 2  , 1  , 0  , } , 
}

local function _bxor(a,b)
    local res, c = 0, 1
    while a > 0 and b > 0 do
        local a2, b2 = a % 16, b % 16
        res = res + tab[a2+1][b2+1]*c
        a = (a-a2)/16
        b = (b-b2)/16
        c = c*16
    end
    res = res + a*c + b*c
    return res
end


local function _bnot(a)   return MAXINT - a end
local function _band(a,b) return ((a+b) - _bxor(a,b))/2 end
local function _bor(a,b)  return MAXINT - _band(MAXINT - a, MAXINT - b) end
local function set_bits(mode, bits)
    return _bor(mode, bits)
end

local function splitpath(string) 
    local dir,file = match(string, "(.-)([^/\\]*)$") 
    dir = match(dir, "(.-)[/\\]?$")
    if dir == '' then
        dir = "/"
    end
    return dir,file
end

local function mk_mode(owner, group, world, sticky)
    sticky = sticky or 0
    return owner * S_UID + group * S_GID + world + sticky * S_SID
end

local function new_meta(mymode, uid, gid, now)
    inode_start = inode_start + 1
    return {
        mode  = mymode,
        ino   = inode_start,
        uid   = uid,
        gid   = gid,
        size  = 0,
        atime = now,
        mtime = now,
        ctime = now
    }
end

-- needed to get the correct / permissions (from FUSE mount user)
local uid,gid,pid,puid,pgid = fuse.context()

-- empty block precalculated: block of \x00 for size BLOCKSIZE
local t = {}
for i=1,BLOCKSIZE do
    push(t, "\000")
end
local empty_block = join(t)


--
-- fs_meta, inode_start and block_nr are the global variables that are needed
-- globally to go over the journal easy
--
inode_start = 1
block_nr    = STRIDE * 4 * 1024 
freelist    = {}
fs_meta     = {}
fs_meta["/"]               = new_meta(mk_mode(7,5,5) + S_IFDIR, uid, gid, time())
fs_meta["/"].directorylist = {}
fs_meta["/"].nlink         = 3
fs_meta["/.journal"]          = new_meta(set_bits(mk_mode(7,5,5), S_IFREG), uid, gid, time())
fs_meta["/.journal"].blockmap = list:new{}
fs_meta["/.journal"].freelist = {[0]=block_nr - 1}

last_journal_time = 0

local journal_fh


--
-- FUSE methods (object)
--
luafs = {
init = function(self, proto_major, proto_minor, async_read, max_write, max_readahead)

    -- open the blockdevice
    journal_fh = assert(io.open(self.metadev, "r+"))
    journal_fh:setvbuf("no")

    -- find the size of it
    local blockdev_size = journal_fh:seek("end",0)
    say("blockdev "..self.metadev.." size:"..blockdev_size)

    --
    -- read in the state the filesystem was at umount, this *must* be done
    -- *before* the update change methods are made a little bit further
    --
    -- FIXME: 'self' cannot be used here, find out how, see also
    --        serializemeta() for more information. Now a record in the
    --        journal is of the form:
    --
    --          luafs.<method>(self, ...)
    --
    --        because luafs is a global that can be accessed (while 'self'
    --        cannot as it is local?!):
    --
    --          loadstring(<journalentry>)()
    --
    --
    say("start reading metadata from "..self.metadev) 
    journal_fh:seek("set",0)
    local journal_last_block = block_nr
    local size = 0
    local i = 1
    local str = ''
    local end_loop = false
    local nextstr
    --local buf = {}
    while i < journal_last_block and not end_loop do
        print("mainloop")
        nextstr = journal_fh:read(BLOCKSIZE)
        str = str..nextstr
        end_loop = true
        for l in split(str, "(.-)\n") do
            if not l or #l == 0 then
                print("end_loop:true")
                break
            end
            --push(buf, l)
            size = size + #l + 1
            print("init:size:"..size..",strlen:"..#str..",l:"..#l)
            --if #buf > 50000 then
                --local s = join(buf, "\n")
                print("EXEC:"..l)
                local status, err = pcall(loadstring(l))
                if not status then
                    print("was error:"..l..",err:"..err)
                    end_loop = true
                    break
                end
                print("EXEC:DONE")
                --buf = {}
            --end
            print("substr start")
            str = substr(str, #l + 2)
            print("substr done:"..#str)
            end_loop = false
        end
        i = i + 1
    end
    --local s = join(buf, "\n")
    --print("EXEC:"..s)
    --assert(loadstring(s))()
    --print("EXEC:DONE")
    --buf = {}
    local journal_meta = fs_meta["/.journal"]
    journal_meta.size = size 
    say("done reading metadata from "..self.metadev) 

    --
    -- loop over all the functions and add a wrapper to write meta data`
    --
    local change_methods = {
        rmdir       = true,
        mkdir       = true,
        create      = true,
        mknod       = true,
        setxattr    = true,
        removexattr = true,
        truncate    = true,
        link        = true,
        unlink      = true,
        symlink     = true,
        chmod       = true,
        chown       = true,
        utime       = true,
        utimens     = true,
        rename      = true,
        _setblock   = true
    }
    for k, _ in pairs(change_methods) do
        local fusemethod  = self[k]
        local prefix      = "luafs."..k.."(self,"
        self[k] = function(self,...) 

            -- always add the time at the end, methods that change the metastate
            -- usually need this to adjust the ctime
            arg[#arg+1] = time()

            -- persistency: make the lua function call
            local o = {}
            for i,w in ipairs(arg) do
                if type(arg[i]) == "number" then
                    o[i] = arg[i]
                elseif type(arg[i]) == "string" then
                    o[i] = format("%q", arg[i])
                end
            end

            -- ....and save it to the metafile
            local je = "if "..arg[#arg].." >= last_journal_time then "..prefix..join(o,",")..") end\n"
            luafs.journal_write(self, journal_meta, je)

            -- really call the function
            return fusemethod(self, unpack(arg))
        end
    end

    -- add the context wrapper
    local context_needing_methods = {
        mkdir       = true,
        create      = true,
        mknod       = true,
        symlink     = true,
        chown       = true
    }
    for k, _ in pairs(context_needing_methods) do
        local fusemethod  = self[k]
        local fusecontext = fuse.context
        self[k] = function(self,...) 
            
            arg[#arg+1], arg[#arg+2] = fusecontext()

            -- really call the function
            return fusemethod(self, unpack(arg))
        end
    end

    return 0
end,

journal_write = function(self, journal_meta, journal_entry)
    journal_fh:seek('set', journal_meta.size)
    journal_fh:write(journal_entry)
    journal_fh:flush()
    journal_meta.size = journal_meta.size + #journal_entry 
    return 
end,

rmdir = function(self, path, ctime)
    if next(fs_meta[path].directorylist) then
        return EEXIST 
    end

    local parent,dir = splitpath(path)
    fs_meta[parent].nlink = fs_meta[parent].nlink - 1
    fs_meta[parent].directorylist[dir] = nil
    fs_meta[parent].ctime = ctime
    fs_meta[parent].mtime = ctime
    fs_meta[path] = nil
    return 0
end,

mkdir = function(self, path, mode, cuid, cgid, ctime)
    if #path > 1024 then
        return ENAMETOOLONG
    end
    local parent,subdir = splitpath(path)
    print("parentdir:"..parent)
    fs_meta[path] = new_meta(mode + S_IFDIR, cuid, cgid, ctime)
    fs_meta[path].directorylist = {}
    fs_meta[path].nlink = 2
    fs_meta[parent].nlink = fs_meta[parent].nlink + 1
    fs_meta[parent].directorylist[subdir] = fs_meta[path]
    fs_meta[parent].ctime = ctime
    fs_meta[parent].mtime = ctime

    print("made dir, mode:"..fs_meta[path].mode)
    return 0
end,

opendir = function(self, path)
    return 0, { t=fs_meta[path].directorylist, k=nil }
end,

readdir = function(self, path, offset, dir_fh)
    local dir_ent, dir_ent_meta = next(dir_fh.t, dir_fh.k)
    if dir_ent == nil then
        return 0, {}
    end
    print("readdir(),v:"..dir_ent)
    dir_fh.k = dir_ent
    local n = path
    if path ~= "/" then n = n .. "/" end
    print("readdir():meta from:"..n..dir_ent)
    n = fs_meta[n..dir_ent]
    return 0, {{d_name=dir_ent, offset=offset + 1, d_type=n.mode, ino=n.ino}}
end,

releasedir = function(self, path, dirent)
    dirent.k = nil
    dirent.t = nil
    -- eventually the last reference to it will disappear
    return 0
end,

open = function(self, path, mode)
    local entity = fs_meta[path]
    if entity then
        return 0, { f=entity }
    else
        return ENOENT, nil
    end
end,

create = function(self, path, mode, flags, cuid, cgid, ctime)
    local parent,file = splitpath(path)
    print("parent:"..parent..",file:"..file)
    if mode == 32768 then
        mode = mk_mode(6,4,4)
    end
    fs_meta[path] = new_meta(set_bits(mode, S_IFREG), cuid, cgid, ctime)
    fs_meta[path].blockmap = list:new()
    fs_meta[parent].directorylist[file] = fs_meta[path]
    fs_meta[parent].ctime = ctime
    fs_meta[parent].mtime = ctime
    return 0, { f=fs_meta[path] }
end,

read = function(self, path, size, offset, obj)
    local entity = fs_meta[path]
    local data   = {}
    local map   = entity.blockmap
    local findx = floor(offset/BLOCKSIZE)
    local lindx = floor((offset + size)/BLOCKSIZE) - 1
    if findx == lindx then
        local b = self:_getblock(data, findx, map[findx]) 
        return 0, substr(b,offset % BLOCKSIZE,offset%BLOCKSIZE+size)
    end
    local str = {}
    for i=findx,lindx-1 do
        push(str, self:_getblock(data, i, map[i]))
    end
    push(str, substr(self:_getblock(data, lindx, map[lindx]),0,offset%BLOCKSIZE+size))
    return 0, join(str)
end,

write = function(self, path, buf, offset, obj)

    -- This call is *NOT* journaled, instead it's _setblock() calls are

    local entity = fs_meta[path]
    local data   = {}
    local map    = entity.blockmap
    local dirty  = {}
    local findx  = floor(offset/BLOCKSIZE)

    -- BLOCKSIZE matches ours + offset falls on the start: just assign
    if offset % BLOCKSIZE == 0 and #buf == BLOCKSIZE then
        print("blocksize matches and offset falls on boundary:"..findx)
		
		-- no need to read in block, it will be written entirely anyway
        data[findx]  = buf
        dirty[findx] = true

    else
        local lindx = floor((offset + #buf - 1)/BLOCKSIZE)

		-- used for both next if/else sections
        local block = self:_getblock(data, findx, map[findx])

        -- fast and nice: same index, but substr() is needed
        if findx == lindx then
            local a = offset % BLOCKSIZE
            local b = a + #buf + 1

            data[findx]  = substr(block,0,a) .. buf .. substr(block,b)
            dirty[findx] = true
        else
            -- simple checks don't match: multiple blocks need to be adjusted.
            -- I'll do that in 3 steps:

            -- start: will exist, as findx!=lindx
            local boffset = offset - findx*BLOCKSIZE
            local a,b = 0,BLOCKSIZE - boffset
            data[findx]  = substr(block, 0, boffset) .. substr(buf, a, b)
            dirty[findx] = true

            -- middle: doesn't necessarily have to exist
            for i=findx+1,lindx-1 do
				-- no need to read in block, it will be written entirely anyway
                a, b = b + 1, b + 1 + BLOCKSIZE
                data[i] = substr(buf, a, b) 
                dirty[i] = true
            end

            -- end: maybe exist, as findx!=lindx, and not ending on blockboundary
        	block = self:_getblock(data, lindx, map[lindx])
            a, b = b + 1, b + 1 + BLOCKSIZE
            data[lindx]  = substr(buf, a, b) .. substr(block, b)
            dirty[lindx] = true

        end
    end

    -- rewrite all blocks to disk
    for i, _ in pairs(dirty) do
        dirty[i] = self:_getnextfreeblocknr(entity)

        self:_writeblock(path, dirty[i], data[i])

		-- make our little cache empty again
		data[i] = nil
    end
    
    -- adjust the metadata in the journal
    local size = entity.size > (offset + #buf) and entity.size or (offset + #buf)
    for i, _ in pairs(dirty) do
        self:_setblock(path, i, dirty[i], size)
    end

    return #buf
end,

_getnextfreeblocknr = function (self, meta)
    meta.freelist = meta.freelist or {}
    local bfree = meta.freelist
    local nextfreeblock = next(bfree)
    if not nextfreeblock then 
        next_free_stride = next(freelist)
        if next_free_stride ~= nil then
            print('_getnextfreeblocknr:'..next_free_stride..
                  ',size:'..freelist[next_free_stride])
            if freelist[next_free_stride] - next_free_stride > STRIDE then
                freelist[next_free_stride] = freelist[next_free_stride] - STRIDE
                next_free_stride = freelist[next_free_stride] + 1
            else 
                print('_getnextfreeblocknr:setting to nil:'..next_free_stride)
                freelist[next_free_stride] = nil
            end
        else
            -- watermark shift
            next_free_stride = block_nr
            block_nr = block_nr + STRIDE
        end
        nextfreeblock = next_free_stride
        bfree[nextfreeblock + 1] = nextfreeblock + STRIDE - 1
    else
        if     bfree[nextfreeblock] ~= nextfreeblock 
           and not bfree[nextfreeblock+1]
           and nextfreeblock < STRIDE*floor(nextfreeblock/STRIDE) + STRIDE then
            bfree[nextfreeblock+1] = bfree[nextfreeblock]
        end
        bfree[nextfreeblock]   = nil
    end
    return nextfreeblock
end,

_addtofreelist = function (self, blocklist)
    for i,b in pairs(blocklist) do
        i = STRIDE * floor(i/STRIDE)
        b = STRIDE * floor(b/STRIDE) + STRIDE - 1
        print("_addtofreelist:i:"..i..",b:"..b)
        freelist[i] = b
    end
    return
end,

_freesingleblock = function (self, b, meta)
    meta.freelist[b] = b
    return
end,

_writeblock = function(self, path, blocknr, blockdata)

    -- this is an actual write of the data to disk. This does not change the
    -- meta journal, that is done seperately, and at the end
    --
    assert(journal_fh:seek('set', BLOCKSIZE*blocknr))
    assert(journal_fh:write(blockdata))
    assert(journal_fh:flush())
end,

_setblock = function(self, path, i, bnr, size, ctime)

    -- a call to this function will also write a meta journal entry, write() is
    -- *NOT* journaled, these calls are instead, so that the writing of data is
    -- always strict

    local e = fs_meta[path]

    -- FIXME: hack ahead: if it does exist. Also pop the freelist when we're
    -- traversing the journal set block_nr ok for journal traversal
    if not self then
        luafs._getnextfreeblocknr(self, e)
        if bnr > block_nr then
            block_nr = bnr
        end
    end

    -- free the previous block
    if e.blockmap[i] then
        luafs._freesingleblock(self, e.blockmap[i], e)
    end
    
    -- reset that block with the new one
    e.blockmap[i] = bnr

    -- adjust meta data
    e.size        = size
    e.ctime       = ctime
    e.mtime       = ctime

    return 0
end,

_getblock = function(self, data, i, blocknr)

    if not data[i] and blocknr ~= nil then
        assert(journal_fh:seek('set', BLOCKSIZE*blocknr))
        local a = assert(journal_fh:read(BLOCKSIZE))
        print("_getblock|return:"..#a)
        if a and #a then
            data[i] = a
        end
    end
    return data[i] or empty_block
end,

release = function(self, path, obj)
    obj.f = nil
    return 0
end,

flush = function(self, path, obj)
    return 0
end,

ftruncate = function(self, path, size, obj)
    return self:truncate(path, size)
end,

truncate = function(self, path, size, ctime)

    if size < 0 then
        return EINVAL
    end

    -- FIXME:
    -- restriction of lua? or fuse.c? or.. maybe find out someday why there's a
    -- weird max and fix it. I want my files to be big! :-)
    if size >= 2147483647 then
        return EFBIG
    end

    local m = fs_meta[path]

    if size > 0 then

        -- update blockmap
        local lindx = floor(size/BLOCKSIZE)

        -- FIXME: free the blocks to the filesystem's freelist!
        list.truncate(m.blockmap, lindx + 1)

        -- FIXME: dirty hack: self == nil is init fase, during run-fase (pre
        -- this init mount()), the block was written allready
        if self then
            local str = self:_getblock({}, lindx, m.blockmap[lindx])

            -- always write as a new block
            local bnr = self:_getnextfreeblocknr(m)

            self:_writeblock(path, bnr, substr(str,0,size%BLOCKSIZE))

            -- this puts an entry in the journal for the block set, with
            -- correct size and all.
            --
            -- Thus, truncate has 2 calls in the journal:
            --   1. truncate()
            --   2. _setblock()
            --
            -- During mount, the journal needs those 2 together, which is in
            -- fact not safe!
            --
            -- This is because I don't want to have no truncate(): then I would
            -- need _setblock() for all null-ed blocks.
            --
            self:_setblock(path, lindx, bnr, size)
        end
    else 

        -- free the blocks: just add to the filesystem's freelist
        luafs._addtofreelist(self, (rawget(m.blockmap, '_original')).list)

        m.freelist = nil
        m.blockmap = list:new()
        m.ctime    = ctime
        m.mtime    = ctime
        m.size     = 0
    end

    return 0
end,

rename = function(self, from, to, ctime)

    -- FUSE handles paths, e.g. a file being moved to a directory: the 'to'
    -- becomes that target directory + "/" + basename(from).
    --

    -- if the target still exists, e.g. when you move a file to another file,
    -- first free the blocks: just add to the filesystem's freelist. For this
    -- we can simply unlink it, just make sure we use the real unlink, not the
    -- journalled one. Of course, we only unlink when it's a file, not in other
    -- cases. unlink here also maintains the nlink parameter.
    if fs_meta[to] and fs_meta[to].blockmap then
        luafs._unlink(self, to, ctime)
    end

    -- rename main node
    fs_meta[to]   = fs_meta[from]
    fs_meta[from] = nil

    -- rename both parent's references to the renamed entity
    local p,e

    -- 'to'
    p, e = splitpath(to)
    fs_meta[p].directorylist[e] = fs_meta[to]
    fs_meta[p].nlink = fs_meta[p].nlink + 1
    fs_meta[p].ctime = ctime
    fs_meta[p].mtime = ctime

    -- 'from'
    p,e = splitpath(from)
    fs_meta[p].directorylist[e] = nil
    fs_meta[p].nlink = fs_meta[p].nlink - 1
    fs_meta[p].ctime = ctime
    fs_meta[p].mtime = ctime

    -- rename all decendants, maybe not such a good idea to use this
    -- mechanism, but don't forget, how many times does one rename e.g.
    -- /usr and such.. ;-). for a plain file (or empty subdir), this is for
    -- isn't even executed (looped actually)
    --
    if fs_meta[to].directorylist then
        local ts = to   .. "/"
        local fs = from .. "/"
        for sub in pairs(fs_meta[to].directorylist) do
            ts = ts .. sub
            fs = fs .. sub
            print("r:"..sub..",to:"..ts..",from:"..fs)
            fs_meta[ts] = fs_meta[fs]
            fs_meta[fs] = nil
        end 
    end

    return 0
end,

symlink = function(self, from, to, cuid, cgid, ctime)
    -- 'from' isn't used,.. that can be even from a seperate filesystem, e.g.
    -- when someone makes a symlink on this filesystem...
    local parent,file = splitpath(to)
    fs_meta[to] = new_meta(mk_mode(7,7,7) + S_IFLNK, cuid, cgid, ctime)
    fs_meta[to].target = from
    fs_meta[parent].directorylist[file] = fs_meta[to]
    fs_meta[parent].ctime = ctime
    fs_meta[parent].mtime = ctime
    return 0
end,

readlink = function(self, path)
    local entity = fs_meta[path]
    if entity then
        return 0, fs_meta[path].target
    else
        return ENOENT, nil
    end
end,

link = function(self, from, to, ctime)
    local entity = fs_meta[from]
    if entity then
        -- update meta
        entity.ctime = ctime
        entity.nlink = (entity.nlink or 1) + 1

        -- 'copy'
        fs_meta[to]  = fs_meta[from]

        -- update the TO parent: add entry + change meta
        local toparent,e = splitpath(to)
        fs_meta[toparent].directorylist[e] = fs_meta[to]
        fs_meta[toparent].ctime = ctime
        fs_meta[toparent].mtime = ctime
        
        return 0
    else
        return ENOENT
    end
end,

unlink = function(self, path, ctime)
    return luafs._unlink(self, path, ctime)
end,

_unlink = function(self, path, ctime)

    local entity = fs_meta[path]
    entity.nlink = (entity.nlink or 1) - 1
    entity.ctime = ctime

    local p,e = splitpath(path)
    fs_meta[p].directorylist[e] = nil
    fs_meta[p].ctime = ctime
    fs_meta[p].mtime = ctime

    -- nifty huh ;-).. : decrease links to the entry + delete *this*
    -- reference from the tree and the meta, other references will see the
    -- decreased nlink from that

    fs_meta[path] = nil

    if entity.nlink == 0 and entity.blockmap then
        luafs._addtofreelist(self, (rawget(entity.blockmap, '_original')).list)
    end

    return 0
end,

mknod = function(self, path, mode, rdev, cuid, cgid, ctime)
    -- only called for non-symlinks, non-directories, non-files and links as
    -- those are handled by symlink, mkdir, create, link. This is called when
    -- mkfifo is used to make a named pipe for instance.
    --
    -- FIXME: support 'plain' mknod too: S_IFBLK and S_IFCHR
    fs_meta[path]         = new_meta(mode, cuid, cgid, ctime)
    fs_meta[path].dev     = rdev

    local parent,file = splitpath(path)
    fs_meta[parent].directorylist[file] = fs_meta[path]
    fs_meta[parent].ctime = ctime
    fs_meta[parent].mtime = ctime
    return 0
end,

chown = function(self, path, uid, gid, cuid, cgid, ctime)
    local entity = fs_meta[path] 
    if entity then

        -- Funny this is.. but this appears to be ext3 on linux behavior.
        -- However, FUSE doesn't give me e.g. -1 -1 as user root, while it
        -- wants the ctime to be adjusted. I think this is the nitty gritty
        -- details that makes this code rather 'not needed' anywayz..
        --
        -- That's the reason why tests 141, 145, 149 and 153 of pjd fail
        -- btw...
        if cuid ~= 0 then
            if not (uid == MAXINT and gid == MAXINT) then
                entity.mode = _band(entity.mode, _bnot(S_SID))
            end
        end
        if uid ~= MAXINT then entity.uid = uid end
        if gid ~= MAXINT then entity.gid = gid end
        entity.ctime = ctime
        return 0
    else
        return ENOENT
    end
end,

chmod = function(self, path, mode, ctime)
    local entity = fs_meta[path] 
    if entity then
        entity.mode  = mode
        entity.ctime = ctime
        return 0
    else
        return ENOENT
    end
end,

utime = function(self, path, atime, mtime)
    local entity = fs_meta[path] 
    if entity then
        entity.atime = atime
        entity.mtime = mtime
        return 0
    else
        return ENOENT
    end
end,


utimens = function(self, path, atime, mtime)
    local entity = fs_meta[path] 
    if entity then
        entity.atime = atime
        entity.mtime = mtime
        return 0
    else
        return ENOENT
    end
end,

access = function(self, path, mode)
    return 0
end,

fsync = function(self, path, isdatasync, obj)
    return 0
end,

fsyncdir = function(self, path, isdatasync, obj)
    return 0
end,

fgetattr = function(self, path, obj)
    return self:getattr(path)
end,

destroy = function(self, return_value_from_init)
    journal_fh:close()
    self:serializemeta()
    return 0
end,

bmap = function(self, path, blocksize, index)
    return 0
end,

getattr = function(self, path)
    if #path > 1024 then
        return ENAMETOOLONG
    end

    -- FIXME: All ENAMETOOLONG needs to implemented better (and correct)
    local dir,file = splitpath(path)
    if #file > 255 then
        return ENAMETOOLONG
    end
    local x = fs_meta[path]
    if not x then
        return ENOENT, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    end 
    if debug then
        print("getattr():"..x.mode..",".. x.ino..",".. (x.dev or '<dev=nil but returning 0>')
              ..",".. (x.nlink or '<nlink=nil but returning 1>')..",".. x.uid..",".. x.gid..",".. x.size..","
              .. x.atime..",".. x.mtime..",".. x.ctime)
    end
    return 0, x.mode, x.ino, x.dev or 0, x.nlink or 1, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

listxattr = function(self, path, size)
    if fs_meta[path] then
        local s = "\0"
        for k,v in pairs(fs_meta[path].xattr or {}) do 
            if type(v) == "string" then
                s = v .. "\0" .. s
            end
        end
        return 0, s
    else
        return ENOENT, nil
    end
end,

removexattr = function(self, path, name)
    if fs_meta[path] and fs_meta[path].xattr then
        fs_meta[path].xattr[name] = nil
        return 0
    else
        return ENOENT
    end
end,

setxattr = function(self, path, name, val, flags)
    local e = fs_meta[path]
    if e then
        e.xattr = e.xattr or {}
        e.xattr[name] = val
        return 0
    else
        return ENOENT
    end
end,

getxattr = function(self, path, name, size)
    local e = fs_meta[path]
    if fs_meta[path] then
        -- xattr 'name' not found is empty string ""
        e.xattr = e.xattr or {}
        return e.xattr[name] or ""
    else
        return ENOENT, ""
    end
end,

statfs = function(self, path)
    local nr_of_blocks      = floor(self.size/BLOCKSIZE)
    local nr_of_free_blocks = nr_of_blocks - (block_nr + 1) + #freelist
    return 
        0,
        BLOCKSIZE, 
        nr_of_blocks, 
        nr_of_free_blocks, 
        nr_of_free_blocks, 
        inode_start,
        MAXINT
end,

_canonicalize_freelist = function(self)
    local last
    for i,v in pairsByKeys(freelist) do
        if not last then
            last = i
        else
            if i == freelist[last] + 1 then
                freelist[last] = freelist[i]
                freelist[i]    = nil
            else
                last = i
            end
        end
    end
    return
end,

serializemeta = function(self)

    -- a hash that transfers inode numbers to the first dumped path, this
    -- serves the purpose of making the hardlinks correct. Of course, we only
    -- keep them here when the number of links > 1. (Or in case a directory is
    -- linked, >2)
    local inode = {}

    -- write the main globals first
    local new_meta_fh = io.open(self.metafile..'.new', 'w')
    new_meta_fh:write('block_nr,inode_start='..block_nr..','..inode_start..'\n')

    -- write the freelist
    self:_canonicalize_freelist()
    local fl = {}
    for i, v in pairs(freelist) do
        push(fl, '['..i..']='..v)
    end
    new_meta_fh:write('freelist = {', join(fl, ','), '}\n')

    -- loop over all filesystem entries
    for k,e in pairs(fs_meta) do
        local prefix = 'fs_meta["'..k..'"]'
        if inode[e.ino] then

            -- just add a link
            new_meta_fh:write(prefix,' = fs_meta["',inode[e.ino],'"]\n')

        else

            -- save that ref for our hardlink tree check
            if (e.directorylist and e.nlink > 2) or (e.nlink and e.nlink > 1) then
                inode[e.ino] = k
            end

            -- regular values + symlink target
            local meta_str = {}
            for key, value in pairs(e) do
                if type(value) == "number" then
                    push(meta_str, key..'='..value)
                elseif type(value) == "string" then
                    push(meta_str, key..'='..format("%q", value))
                end
            end
            new_meta_fh:write(prefix,'={', join(meta_str, ","))

            -- metadata:xattr
            if e.xattr then
                local xattr_str = {}
                for x,v in pairs(e.xattr) do
                    if type(v) == 'boolean' and v == true then
                        push(xattr_str, '["'..x..'"]=true')
                        break
                    end
                    if type(v) == 'boolean' and v == false then
                        push(xattr_str, '["'..x..'"]=false')
                        break
                    end
                    push(xattr_str, '["'..x..'"]='..format('%q',v))
                end
                push(meta_str, 'xattr={'..join(xattr_str, ',')..'}')
            end

            -- 'real' data entry stuff
            local t = {}
            if e.directorylist then

                -- directorylist
                for d, _ in pairs(e.directorylist) do
                    push(t, '["'..d..'"]=true')
                end
                new_meta_fh:write(',directorylist={',join(t, ','),'}}\n')

            elseif e.blockmap then

                -- dump the freelist
                if e.freelist then
                    fl = {}
                    for i, v in pairs(e.freelist) do
                        push(fl, '['..i..']='..v)
                    end
                    new_meta_fh:write(',freelist={',
                        join(fl, ','),
                    '}')
                end

                -- dump the blockmap
                new_meta_fh:write(',blockmap=list:new{',
                    list.tostring(e.blockmap),
                '}}\n')

            else

                -- was a symlink, node,.. just close the tag
                new_meta_fh:write('}\n')
            end
        end
    end
    new_meta_fh:close()

    return 0
end,

metadev  = "/dev/loop7",
metafile = "/home/tim/tmp/fs/test.lua",
size     = 1 * 1024 * 1024 * 1024

}

--
-- commandline option parsing/checking section
--
-- -s option: single threaded. multithreaded also works, but no performance
-- gain (yet), in fact, it's slower.
--
options = {
    'luafs',
    ...
}
fuse_options = {
    '-s', 
    '-f', 
    '-oallow_other',
    '-odefault_permissions',
    '-ohard_remove', 
    '-oentry_timeout=0',
    '-onegative_timeout=0',
    '-oattr_timeout=0',
    '-ouse_ino',
    '-oreaddir_ino',
    '-omax_read=131072',
    '-omax_readahead=131072',
    '-omax_write=131072',

}

for i,w in ipairs(fuse_options) do
    push(options, w)
end

-- check the mountpoint
local here = lfs.currentdir()
if not lfs.chdir(options[2]) then
    print("mountpoint "..options[2].." does not exist")
    os.exit(1)
end
lfs.chdir(here)

-- simple options check
if select('#', ...) < 1 then
    print(string.format("Usage: %s <mount point> [fuse mount options]", arg[0]))
    os.exit(1)
end


--
-- debugging section
--
local debug = 0
for i,w in ipairs(options) do
    if w == '-d'  then
        debug = 1
    end
end
oldprint = print
function say(...)
    return oldprint(time(), unpack(arg))
end
if debug == 0 then 
    function print() end
end

say("start")

-- debug?
if debug then
    for k, f in pairs(luafs) do
        if type(f) == 'function' then
            luafs[k] = function(self,...) 
                
                local d = {}
                for i,v in ipairs(arg) do
                    d[i] = tostring(v) 
                end
                print("function:"..k.."(),args:"..join(d, ","))

                -- really call the function
                return f(self, unpack(arg))
            end
        end
    end
end

for i,w in ipairs(options) do
    print("option:"..w)
end

--
-- start the main fuse loop
--
print("main()")
fuse.main(luafs, options)
