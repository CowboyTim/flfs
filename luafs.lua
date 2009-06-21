#!/usr/bin/env lua

local fuse = require 'fuse'
local lfs  = require 'lfs'
local list = require 'list'

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
local ENOSPC       = -28
local ENAMETOOLONG = -36
local ENOSYS       = -38
local ENOTEMPTY    = -39
local ENOATTR      = -516
local ENOTSUPP     = -524

local BLOCKSIZE    = 4096
local STRIDE       = 1
local MAXINT       = 2^32 -1

--
-- shortcuts, lua speedups in fact
--
local substr    = string.sub
local floor     = math.floor
local time      = os.time
local join      = table.concat
local push      = table.insert
local pop       = table.remove
local sort      = table.sort
local format    = string.format
local split     = string.gmatch
local match     = string.match
local find      = string.find

local function shift(t)
    return pop(t,1)
end

-- padding function
local function pad(str, count, what)
    str = str or ''
    local t = {}
    for i=#str,count-1 do
        push(t, what or "\000")
    end
    return str..join(t)
end

-- logging methods
local oldprint = print
local function say(...)
    return oldprint(time(), unpack(arg))
end
local debug = 0

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


local function _bxor(x, y)
   local z = 0
   for i = 0, 31 do
      if (x % 2 == 0) then                      -- x had a '0' in bit i
         if ( y % 2 == 1) then                  -- y had a '1' in bit i
            y = y - 1 
            z = z + 2 ^ i                       -- set bit i of z to '1' 
         end
      else                                      -- x had a '1' in bit i
         x = x - 1
         if (y % 2 == 0) then                   -- y had a '0' in bit i
            z = z + 2 ^ i                       -- set bit i of z to '1' 
         else
            y = y - 1 
         end
      end
      y = y / 2
      x = x / 2
   end
   return z
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
    return owner * S_UID + group * S_GID + world + (sticky or 0) * S_SID
end

local metafile = "/home/tim/tmp/fs/test.lua" -- FIXME: implement correct state save

-- FIXME: implement correct journal size'ing
block_nr           = 256 * 1024 * 1024 / BLOCKSIZE
inode_start        = 1
max_block_nr       = 0
blocks_in_freelist = 0

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
local empty_block = pad('', BLOCKSIZE, '\000')


--
-- fs_meta, inode_start and block_nr are the global variables that are needed
-- globally to go over the journal easy
--
--

fs_meta        = {}
freelist       = {}
freelist_index = {}

local fs_meta              = fs_meta
fs_meta["/"]               = new_meta(mk_mode(7,5,5) + S_IFDIR, uid, gid, time())
fs_meta["/"].directorylist = {}
fs_meta["/"].nlink         = 2

local journal_fh

-- divide the journal section into 2. Note that although they have different
-- names, they are and will be interchangeable sections: the journal can hold
-- state, and the state can hold the journal. In fact, they will always hold
-- both even, we just switch between the two sections.
local m = floor(block_nr/2)
journals = {
    current = {freelist={[0] = m - 1},       size=0},
    other   = {freelist={[m] = block_nr - 1},size=0}
}
local journals = journals


--
-- This function finds a new free block, with a preferred stride size. It goes
-- looking in the file's currently assigned free list first. If nothing is free
-- anymore, it searches the global freelist. If nothing is found there, it
-- shifts the watermark.
--
-- It raises an exception if no free block can be found, thus when no space is
-- available anymore
--
local function getnextfreeblocknr(meta, stride_wanted)
    local bfree = meta.freelist
    if not bfree then
        meta.freelist = {}
        bfree = meta.freelist
    end
    local nextfreeblock = next(bfree)
    if not nextfreeblock then 
        if #freelist_index > 0 then
            next_free_stride = freelist_index[1]
            print('getnextfreeblocknr:'..next_free_stride..
                  ',size:'..freelist[next_free_stride])
            if freelist[next_free_stride] - next_free_stride >= stride_wanted then
                freelist[next_free_stride + stride_wanted] = freelist[next_free_stride]
                freelist_index[1] = next_free_stride + stride_wanted
            else 
                print('getnextfreeblocknr:setting to nil:'..next_free_stride)
                shift(freelist_index)
            end
            freelist[next_free_stride] = nil
            blocks_in_freelist = blocks_in_freelist - stride_wanted
        else
            -- watermark shift
            next_free_stride = block_nr
            block_nr = block_nr + stride_wanted
            if block_nr >= max_block_nr then
                block_nr = block_nr - stride_wanted
                error({code=1, message="Disk Full"})
            end
        end
        nextfreeblock = next_free_stride
        if stride_wanted > 1 then
            bfree[nextfreeblock + 1] = nextfreeblock + stride_wanted - 1
        end
    else
        print("from file freelist:"..nextfreeblock..',bfree[nextfreeblock]:'..bfree[nextfreeblock])
        if     bfree[nextfreeblock] ~= nextfreeblock 
           and not bfree[nextfreeblock+1]
           and nextfreeblock < stride_wanted*floor(nextfreeblock/stride_wanted) + stride_wanted then
            bfree[nextfreeblock+1] = bfree[nextfreeblock]
        end
        bfree[nextfreeblock]   = nil
    end
    return nextfreeblock
end


--
-- This method is used when the filesystem state needs to be serialized: we
-- sort the freelist + collapse the adjacent blocks into longer block strides
-- as much as possible
--
local function _canonicalize_freelist()
    freelist_index = {}
    local last
    for i,v in pairsByKeys(freelist) do
        if not last then
            last = i
            push(freelist_index, last)
        else
            if i == freelist[last] + 1 then
                freelist[last] = freelist[i]
                freelist[i]    = nil
            else
                last = i
                push(freelist_index, last)
            end
        end
    end
    return
end


--
-- This method add the blocks in the argument (typically from a file) to the
-- freelist again
--
local function addtofreelist(blocklist)
    if not blocklist then 
        return  
    end
    for i,b in pairs(blocklist) do
        print("addtofreelist:i:"..i..",b:"..b)
        freelist[i] = b
        blocks_in_freelist = blocks_in_freelist + b - i + 1
        push(freelist_index, i)
    end
    -- FIXME: bad idea, implement a better one
    --luafs._canonicalize_freelist(self)
    return
end


--
-- This method frees a single block. This is typically upon re writing the
-- file: a new block is always requested and the old block needs to be freed,
-- this method serves for freeing that new block. It is currently added to the
-- freelist of the file itself
--
local function freesingleblock(b, meta)
    meta.freelist[b] = b
    return
end


local function readdata(start, size)
    print("readdata():"..start..","..size)
    assert(journal_fh:seek('set', start))
    local a = assert(journal_fh:read(size))
    print("readdata|return:"..#a)
    return a
end


--
-- This method reads a block from the block device (or file)
--
local function readblock(blocknr)
    print("readblock():"..tostring(blocknr))
    
    if blocknr ~= nil then
        local a = readdata(BLOCKSIZE*blocknr, BLOCKSIZE)
        if a and #a then
            return a
        end
    end
    return empty_block
end

--
-- This method writes a block to the block device (or file)
--
local function writeblock(path, blocknr, blockdata)
    assert(journal_fh:seek('set', BLOCKSIZE*blocknr))
    assert(journal_fh:write(blockdata))
    assert(journal_fh:flush())
end

--
-- This method writes a journal entry to the journal
--
local function journal_write(...)
    for _, journal_entry in ipairs(arg) do

        local journal_meta = journals['current']
        local current_js   = journal_meta.size
        local next_bi      = floor((current_js+#journal_entry)/BLOCKSIZE)
        local first_free_block = next(journal_meta.freelist)
        print("journal_write:current_js:"..current_js..
              ",next_bi:"..next_bi..
              ",first_free_block:"..first_free_block..
              ",journal_entry_size:"..#journal_entry)

        -- new journal? clear first block too
        if current_js == 0 then
            journal_fh:seek('set', BLOCKSIZE * first_free_block)
            journal_fh:write(pad('', BLOCKSIZE, ' '))
            journal_fh:flush()
        end

        -- clear next 2 blocks if we're switching block
        if next_bi ~= floor(current_js/BLOCKSIZE) then

            -- journal overloop?
            if first_free_block + next_bi >= journal_meta.freelist[first_free_block] then
                -- journal wouldn't fit anymore: save the state at the other
                -- journal space and switch to it
                -- FIXME: euh, infinite loop when the state also doesn't fit in
                --        the space preserved...
                serializemeta()
                return journal_write(unpack(arg))
            end
            journal_fh:seek('set', BLOCKSIZE * (first_free_block + next_bi))
            journal_fh:write(pad('', BLOCKSIZE, ' '), empty_block)
            journal_fh:flush()
        end

        -- jump to the journal's size (+ the offset=*which* journal) and write
        -- journal entry
        journal_fh:seek('set', (BLOCKSIZE * first_free_block) + current_js)
        journal_fh:write(journal_entry)
        journal_fh:flush()
        
        -- and adjust new size
        journal_meta.size = current_js + #journal_entry 
    end
    return true 
end


-- 
-- This method serializes the entire filesystem meta state in one go on the
-- block device (or file) in the meta journal section.
--
local function serializemeta()

    say("making a new state")

    -- we switch the journal meta's
    journals['current'], journals['other'] = journals['other'], journals['current']

    -- reset that new journal we're about to write in
    journals['current'].size = 0

    -- a hash that transfers inode numbers to the first dumped path, this
    -- serves the purpose of making the hardlinks correct. Of course, we only
    -- keep them here when the number of links > 1. (Or in case a directory is
    -- linked, >2)
    local inode = {}

    -- write the main globals first
    journal_write('block_nr,inode_start,blocks_in_freelist='
                  ..block_nr..','..inode_start..','..blocks_in_freelist..'\n')

    -- write the freelist
    _canonicalize_freelist()
    local fl = {}
    for i, v in pairs(freelist) do
        push(fl, '['..i..']='..v)
    end
    journal_write('freelist = {', join(fl, ','), '}\n')
    journal_write('freelist_index = {', join(freelist_index, ','), '}\n')

    local listtostring = list.tostring

    -- loop over all filesystem entries
    for k,e in pairs(fs_meta) do
        local prefix = 'fs_meta["'..k..'"]'
        if inode[e.ino] then

            -- just add a link
            journal_write(prefix,' = fs_meta["',inode[e.ino],'"]\n')

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
            journal_write(prefix,'={', join(meta_str, ","))

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
                journal_write(',directorylist={',join(t, ','),'}}\n')

            elseif e.blockmap then

                -- dump the freelist
                if e.freelist and next(e.freelist) then
                    fl = {}
                    for i, v in pairs(e.freelist) do
                        push(fl, '['..i..']='..v)
                    end
                    journal_write(',freelist={',
                        join(fl, ','),
                    '}')
                end

                -- dump the blockmap
                journal_write(',blockmap=list:new{',
                    listtostring(e.blockmap),
                '}}\n')

            else

                -- was a symlink, node,.. just close the tag
                journal_write('}\n')
            end
        end
    end

    say("making a new state:done,size:"..journals['current'].size)
    say("switching state to 'other'")
    journals['current'], journals['other'] = journals['other'], journals['current']
    journals['current'].size = 0
    local init_journal = [[
        local journals = _G.journals
        journals['current'], journals['other'] = journals['other'], journals['current']

    ]]
    journal_write(pad(init_journal, BLOCKSIZE, ' '))
    journals['current'], journals['other'] = journals['other'], journals['current']
    

    return 0
end

_G.serializemeta = serializemeta



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
    max_block_nr = floor(blockdev_size / BLOCKSIZE) - STRIDE
    say("blockdev "..self.metadev.." size:"..blockdev_size..",start block:"..block_nr..",max block:"..max_block_nr)
    

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
    --          load(<journalentry>)()
    --
    --
    say("start reading metadata from "..self.metadev) 
    local start_done = false
    journal_fh:seek("set",0)
    local journal_f,err=load(function() 
        if start_done then
            return nil
        end
        start_done = true
        return journal_fh:read(BLOCKSIZE) 
    end)
    if journal_f then
        local status, err = pcall(journal_f)
        if not status then
            print("was error:"..err)
        end
    end
    local position = BLOCKSIZE * (next(journals['current'].freelist))
    say("reading journal from "..position)
    journal_fh:seek("set",position)

    local journal_size = 0
    local journal_str  = ''
    local start_done   = false

    local journal_f,err=load(function()
        if not start_done then
            start_done = true
            return [[
                local chunk_function
                local fs_meta = _G.fs_meta
            ]]
        end
        local nstr = journal_fh:read(BLOCKSIZE)
        -- first char of the next block is null, thus it is the end of
        -- the journal/state, so we end the loop
        while nstr and substr(nstr,1,1) ~= '\000' do
            journal_str = journal_str..nstr
            local last_i
            local i = find(journal_str, "\n", 1, true)
            while i do
                last_i = i
                i = find(journal_str, "\n", i+1, true)
            end 
            if last_i then
                print("last_i:"..last_i)
                local l = substr(journal_str, 0, last_i)
                journal_size = journal_size + #l
                print(l)
                journal_str = substr(journal_str, #l + 1)
                print("return, len:"..#journal_str)
                return 
                    [[ chunk_function=function() ]]
                    ..l..
                    [[ 
                       end
                       chunk_function() 
                    ]]
            end
            nstr = journal_fh:read(BLOCKSIZE)
            print("len:"..#journal_str)
        end
        return nil
    end)
    if not journal_f then
        error(err)
    end
    local status, err = pcall(journal_f)
    if not status then
        print("was error:"..err)
        error(err)
    end
    journals['current'].size = journal_size 
    if journal_size == 0 then
        -- init, was a clean filesystem
        say("initializing filesystem")
        local init_journal = [[
            -- we're current: at block 0, we just write some code to make sure
            -- that is understandeable, it is basically pretty pointless at
            -- this point. Note that this 'journal entry' is padded until
            -- BLOCKSIZE.

        ]]
        journal_write(pad(init_journal, BLOCKSIZE, ' '))
    end

    say("done reading metadata from "..self.metadev..", journal size was:"..journal_size) 
    say("current parameters: inode_start:"..inode_start..",block_nr:"..block_nr) 

    --
    -- loop over all the functions and add a wrapper to write meta data`
    --
    local change_methods = {
        'rmdir',
        'mkdir',
        'create',
        'mknod',
        'setxattr',
        'removexattr',
        'truncate',
        'link',
        'unlink',
        'symlink',
        'chmod',
        'chown',
        'utime',
        'utimens',
        'rename',
        '_setblock'
    }
    for _, k in ipairs(change_methods) do
        local fusemethod    = self[k]
        local prefix        = "luafs."..k.."(self,"
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

            -- ....and save it to the journal
            local journal_entry = prefix..join(o,",")..")\n"
            if not journal_write(journal_entry) then
                return ENOSPC
            end

            -- really call the function
            return fusemethod(self, unpack(arg))
        end
    end

    -- add the context wrapper
    local context_needing_methods = { 'mkdir', 'create', 'mknod', 'symlink', 'chown' }
    for _, k in ipairs(context_needing_methods) do
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
    local msize = offset + size
    if msize > fs_meta[path].size then
        local fsize = fs_meta[path].size
        if offset >= fsize then
            return 0, ''
        end
        size  = fsize - offset
        msize = offset + size
    end
 
    local map    = fs_meta[path].blockmap
    local findx  = floor(offset/BLOCKSIZE)
    local lindx  = floor(msize/BLOCKSIZE)

    local offset_block = offset%BLOCKSIZE

    print("findx:"..findx..",lindx:"..lindx)
    if msize%BLOCKSIZE == 0 then
        -- we don't need/want that last block
        lindx = lindx - 1
    end

    local str = {}

    local first_bn, last_bn
    for i=findx,lindx do 
        print("asking for:"..i)
        local next_bn = map[i]
        if next_bn and ((last_bn and (last_bn + 1 == next_bn)) or not last_bn) then
            print("exists")
            last_bn = next_bn
            if not first_bn then
                first_bn = next_bn
            end
        else
            if first_bn then
                print("readdata in loop, next_bn:"..tostring(next_bn))
                local start_block = first_bn*BLOCKSIZE
                push(str, readdata(
                    start_block, BLOCKSIZE + last_bn * BLOCKSIZE - start_block
                ))
            end
            first_bn, last_bn = nil, nil
            if not next_bn then
                push(str, empty_block)
            else
                last_bn = next_bn
                if not first_bn then
                    first_bn = next_bn
                end
            end
        end
    end
    if first_bn then
        local start_block = first_bn*BLOCKSIZE
        push(str, readdata(
            start_block, BLOCKSIZE + last_bn * BLOCKSIZE - start_block
        ))
    end

    if offset_block ~= 0 then
        print("offset not on boundary:"..offset_block)
        str[1] = substr(str[1],offset_block)
    end

    if msize  % BLOCKSIZE ~= 0 then
        print("offset+msize not on boundary:"..msize)
        local s = (msize%BLOCKSIZE) + (#(str[#str])/BLOCKSIZE - 1)*BLOCKSIZE
        str[#str] = substr(str[#str],0,s)
    end
    return 0, join(str)
end,

write = function(self, path, buf, offset, obj)

    -- This call is *NOT* journaled, instead the resulting _setblock() calls
    -- are.. we don't want to rewrite on journal traversal, we just want to set
    -- the blocks again

    local entity = fs_meta[path]
    local data   = {}
    local map    = entity.blockmap
    local findx  = floor(offset/BLOCKSIZE)
    local sorteddata = {} 

    -- BLOCKSIZE matches ours + offset falls on the start: just assign
    if offset % BLOCKSIZE == 0 and #buf == BLOCKSIZE then
        print("blocksize matches and offset falls on boundary:"..findx)
		
		-- no need to read in block, it will be written entirely anyway
        data[findx]  = buf
        push(sorteddata,findx)

    else
        local lindx = floor((offset + #buf - 1)/BLOCKSIZE)

        print("findx:"..findx..",lindx:"..lindx)

		-- used for both next if/else sections
        local block = readblock(map[findx])

        -- fast and nice: same index, but substr() is needed
        if findx == lindx then
            local a = offset % BLOCKSIZE
            local b = a + #buf + 1

            data[findx]  = substr(block,0,a) .. buf .. substr(block,b)
            push(sorteddata,findx)
        else
            -- simple checks don't match: multiple blocks need to be adjusted.
            -- I'll do that in 3 steps:

            -- start: will exist, as findx!=lindx
            local boffset = offset - findx*BLOCKSIZE
            local a,b = 0,BLOCKSIZE - boffset
            data[findx]  = substr(block, 0, boffset) .. substr(buf, a, b)
            push(sorteddata,findx)

            -- middle: doesn't necessarily have to exist
            for i=findx+1,lindx-1 do
				-- no need to read in block, it will be written entirely anyway
                a, b = b + 1, b + 1 + BLOCKSIZE
                data[i] = substr(buf, a, b) 
                push(sorteddata,i)
            end

            -- end: maybe exist, as findx!=lindx, and not ending on blockboundary
        	block = readblock(map[lindx])
            a, b = b + 1, b + 1 + BLOCKSIZE
            data[lindx]  = substr(buf, a, b) .. substr(block, b)
            push(sorteddata,lindx)

        end
    end

    -- rewrite all blocks to disk
    for _, blockdata_i in ipairs(sorteddata) do

        -- find a new block that's free
        local ok, new_block_nr = pcall(getnextfreeblocknr, entity, STRIDE)
        if not ok then
            obj.errorcode = ENOSPC
            return ENOSPC
        end
        
        -- really write the data to the new block
        writeblock(path, new_block_nr, data[blockdata_i])

        -- save the blocknr for the journal
        data[blockdata_i] = new_block_nr
    end
    
    -- adjust the metadata in the journal, we piggyback the new size in this
    -- call. This way, when traversing the journal, we can set the size correct
    local size = entity.size > (offset + #buf) and entity.size or (offset + #buf)
    for _, blockdata_i in ipairs(sorteddata) do
        self:_setblock(path, blockdata_i, data[blockdata_i], size)
    end

    return #buf
end,

_setblock = function(self, path, i, bnr, size, ctime)

    -- a call to this function will also write a meta journal entry, write() is
    -- *NOT* journaled, these calls are instead, so that the writing of data is
    -- always strict

    local e = fs_meta[path]

    -- FIXME: hack ahead: when traversing the journal, self is nil. So we
    -- pretent to requested a block here, just like it is done in write()
    -- itself. The returned block should be the same as bnr here I think.
    if not self then
        local dummy = getnextfreeblocknr(e, STRIDE)
        if dummy ~= bnr then
            error("Internal error: bnr~=dummy: bnr:"..
                    bnr..",getnextfreeblocknr():"..dummy)
        end
        if bnr > block_nr then
            block_nr = bnr
        end
    end

    -- free the previous block
    if e.blockmap[i] then
        freesingleblock(e.blockmap[i], e)
    end
    
    -- reset that block with the new one
    e.blockmap[i] = bnr

    -- adjust meta data
    e.size        = size
    e.ctime       = ctime
    e.mtime       = ctime

    return 0
end,

release = function(self, path, obj)
    obj.f = nil
    return 0
end,

flush = function(self, path, obj)
    if obj and obj.errorcode then
        return obj.errorcode
    end
    return 0
end,

ftruncate = function(self, path, size, obj)
    return self:truncate(path, size)
end,

truncate = function(self, path, size, ctime)

    if size < 0 then
        return EINVAL
    end

    local m = fs_meta[path]

    if size > 0 then

        -- find the blocknr that might need an update
        local lindx = floor(size/BLOCKSIZE)

        -- if the truncate call would make it bigger: just adjust the size, no
        -- point in allready allocating a block
        if size >= m.size then
            m.size = size

        else
            -- new size would be smaller: update at least 1 block + give all 
            -- the remainder truncated blocks back to the freelist

            -- free the blocks to the filesystem's freelist!
            local remainder = list.truncate(m.blockmap, lindx + 1)
            addtofreelist(m.freelist)
            addtofreelist(remainder)
        
        end

        -- update that lindx block, if it existed: can happen when file grows
        -- or shrinks because a truncate's size can even be 1 byte

        -- FIXME: dirty hack: self == nil is init fase, during run-fase (pre
        --        this init mount()), the block was written allready
        if self and  m.blockmap[lindx] then
            local str = readblock(m.blockmap[lindx])

            -- always write as a new block
            local ok, new_block_nr = pcall(getnextfreeblocknr, m, STRIDE)
            if not ok then
                return ENOSPC
            end

            writeblock(path, new_block_nr, substr(str,0,size%BLOCKSIZE))

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
            self:_setblock(path, lindx, new_block_nr, size)
        end
    else 

        -- free the blocks: just add to the filesystem's freelist
        addtofreelist(m.freelist)
        addtofreelist((rawget(m.blockmap, '_original')).list)

        m.freelist = nil

    end

    m.blockmap = list:new()
    m.ctime    = ctime
    m.mtime    = ctime
    m.size     = size

    return 0
end,

rename = function(self, from, to, ctime)

    -- FUSE handles paths, e.g. a file being moved to a directory: the 'to'
    -- becomes that target directory + "/" + basename(from).
    --

    if fs_meta[to] then

        -- target is a non-empty directory? return ENOTEMPTY errno.h
        if fs_meta[to].directorylist and next(fs_meta[to].directorylist) then
            return ENOTEMPTY
        end

        -- if the target still exists, e.g. when you move a file to another
        -- file,first free the blocks: just add to the filesystem's freelist. 
        -- For this we can simply unlink it, just make sure we use the real 
        -- unlink, not the journalled one. Of course, we only unlink when 
        -- it's a file, not in other cases. unlink here also maintains the 
        -- nlink parameter.

        if fs_meta[to].blockmap then
            luafs._unlink(self, to, ctime)
        end
    end

    -- rename main node
    fs_meta[to]   = fs_meta[from]
    fs_meta[from] = nil

    -- ctime of the target changes
    fs_meta[to].ctime = ctime

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
    -- NOTE: 'to' here is of course the freshly moved entry, the previous 'to'
    --       if any is gone, and will be garbage collected.
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

    if entity.nlink == 0 then
        if entity.freelist then
            addtofreelist(entity.freelist)
        end
        if entity.blockmap then
            addtofreelist((rawget(entity.blockmap, '_original')).list)
        end
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
    serializemeta()
    journal_fh:flush()
    journal_fh:close()
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
    local e = fs_meta[path]
    if e then
        if e.xattr then
            e.xattr[name] = nil
        end
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
    if e then
        -- xattr 'name' not found is empty string ""
        e.xattr = e.xattr or {}
        return e.xattr[name] or ""
    else
        return ENOENT, ""
    end
end,

statfs = function(self, path)
    local nr_of_free_blocks = max_block_nr - (block_nr + 1) + blocks_in_freelist
    return 
        0,
        BLOCKSIZE, 
        max_block_nr, 
        nr_of_free_blocks, 
        nr_of_free_blocks, 
        inode_start,
        MAXINT
end,

}

--
-- commandline option parsing/checking section
--
-- -s option: single threaded. multithreaded also works, but no performance
-- gain (yet), in fact, it's slower.
--
local default_fuse_options = {
    '-s', 
    '-f', 
    '-oallow_other',
    '-odefault_permissions',
    '-ohard_remove', 
    '-oentry_timeout=0',
    '-onegative_timeout=0',
    '-oattr_timeout=0',
    '-ouse_ino',
    --'-odirect_io',
    '-oreaddir_ino',
    '-omax_read=131072',
    '-omax_readahead=131072',
    '-omax_write=131072',
}
for i,w in ipairs(default_fuse_options) do
    push(arg, w)
end

say("using block device "..arg[1])

-- check the mountpoint
local here = lfs.currentdir()
if not lfs.chdir(arg[2]) then
    print("mountpoint "..arg[2].." does not exist")
    os.exit(1)
end
lfs.chdir(here)

-- simple options check
if select('#', ...) < 1 then
    print(format("Usage: %s <device|file> <mount point> [fuse mount options]", arg[0]))
    os.exit(1)
end

--
-- debugging section: work with closures
--
for i,w in ipairs(arg) do
    if w == '-d' then
        debug = 1
    end
end
if debug == 0 then 
    function print() end
else
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

say("starting luafs fuse daemon")
for i,w in ipairs(arg) do
    say("option:"..w)
end

-- set correct block device (or file) from the options at commandline
luafs.metadev = arg[1]

--
-- start the main fuse loop: gives away the control to the C, which in turn
-- gives the control back to this lua vm instance upon FUSE-interrupts for the
-- different  luaf methods here
--
fuse.main(luafs, arg)
