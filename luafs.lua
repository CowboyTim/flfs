#!/usr/bin/env lua

local fuse = require 'fuse'

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

-- For access(), taken from unistd.h
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
local MAXINT       = 2^32 -1

local substr    = string.sub
local floor     = math.floor
local time      = os.time
local concat    = table.concat
local arrayadd  = table.insert
local format    = string.format

local t = {}
for i=1,BLOCKSIZE do
    arrayadd(t, "\000")
end
local empty_block = concat(t)

local tab = {  -- tab[i+1][j+1] = xor(i, j) where i,j in (0-15)
  {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, },
  {1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14, },

  {2, 3, 0, 1, 6, 7, 4, 5, 10, 11, 8, 9, 14, 15, 12, 13, },
  {3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12, },
  {4, 5, 6, 7, 0, 1, 2, 3, 12, 13, 14, 15, 8, 9, 10, 11, },
  {5, 4, 7, 6, 1, 0, 3, 2, 13, 12, 15, 14, 9, 8, 11, 10, },
  {6, 7, 4, 5, 2, 3, 0, 1, 14, 15, 12, 13, 10, 11, 8, 9, },
  {7, 6, 5, 4, 3, 2, 1, 0, 15, 14, 13, 12, 11, 10, 9, 8, },
  {8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7, },
  {9, 8, 11, 10, 13, 12, 15, 14, 1, 0, 3, 2, 5, 4, 7, 6, },
  {10, 11, 8, 9, 14, 15, 12, 13, 2, 3, 0, 1, 6, 7, 4, 5, },
  {11, 10, 9, 8, 15, 14, 13, 12, 3, 2, 1, 0, 7, 6, 5, 4, },
  {12, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3, },
  {13, 12, 15, 14, 9, 8, 11, 10, 5, 4, 7, 6, 1, 0, 3, 2, },
  {14, 15, 12, 13, 10, 11, 8, 9, 6, 7, 4, 5, 2, 3, 0, 1, },
  {15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, },
}

local function _bxor (a,b)
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


local function _bnot(a) return MAXINT - a end

local function _band(a,b) return ((a+b) - _bxor(a,b))/2 end

local function _bor(a,b) return MAXINT - _band(MAXINT - a, MAXINT - b) end

local function set_bits(mode, bits)
    return _bor(mode, bits)
end

function string:splitpath() 
    local dir,file = self:match("(.-)([^/\\]*)$") 
    dir = dir:match("(.-)[/\\]?$")
    if dir == '' then
        dir = "/"
    end
    return dir,file
end

local function mk_mode(owner, group, world, sticky)
    sticky = sticky or 0
    return owner * S_UID + group * S_GID + world + sticky * S_SID
end

local inode_start = 1
local block_nr  = 0

local function getnextblocknr (self)
    block_nr = block_nr + 1
    return block_nr
end



local function new_meta(mymode, uid, gid, now)
    inode_start = inode_start + 1
    return {
        xattr = {[-1] = true},
        mode  = mymode,
        ino   = inode_start,
        dev   = 0,
        nlink = 2,
        uid   = uid,
        gid   = gid,
        size  = 0,
        atime = now,
        mtime = now,
        ctime = now
    }
end

local uid,gid,pid,puid,pgid = fuse.context()
fs_meta = {
    ["/"] = new_meta(mk_mode(7,5,5) + S_IFDIR, uid, gid, time())
}
fs_meta["/"].directorylist = {}

luafs   = {

--init = function(self, connection_info)
--    return {}
--end,

rmdir = function(self, path, ctime)
    if next(fs_meta[path].directorylist) then
        return EEXIST 
    end

    local parent,dir = path:splitpath()
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
    local parent,subdir = path:splitpath()
    print("parentdir:"..parent)
    fs_meta[path] = new_meta(mode + S_IFDIR, cuid, cgid, ctime)
    fs_meta[path].directorylist = {}
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
    local parent,file = path:splitpath()
    print("parent:"..parent..",file:"..file)
    if mode == 32768 then
        mode = mk_mode(6,4,4)
    end
    fs_meta[path] = new_meta(set_bits(mode, S_IFREG), cuid, cgid, ctime)
    fs_meta[path].nlink = 1
    fs_meta[path].contents = {}
    fs_meta[path].blockmap = {}
    fs_meta[parent].directorylist[file] = fs_meta[path]
    fs_meta[parent].ctime = ctime
    fs_meta[parent].mtime = ctime
    return 0, { f=fs_meta[path] }
end,

read = function(self, path, size, offset, obj)
    local data  = obj.f.contents
    local map   = obj.f.blockmap
    local findx = floor(offset/BLOCKSIZE)
    local lindx = floor((offset + size)/BLOCKSIZE)
    if findx == lindx then
        local b = self:_getblock(data, findx, map[findx]) 
        return 0, substr(b,offset % BLOCKSIZE,offset%BLOCKSIZE+size)
    end
    local str = {}
    for i=findx,lindx-1 do
        arrayadd(str, self:_getblock(data, i, map[i]))
    end
    arrayadd(str, substr(self:_getblock(data, lindx, map[lindx]),0,offset%BLOCKSIZE+size))
    return 0, concat(str)
end,

_getblock = function(self, data, i, blocknr)

    if not data[i] and blocknr ~= nil then
        print("_getblock|readblock:i:"..i..",blocknr:"..(blocknr or '<nil>'))
        fh = io.open(self.datadir.."/"..blocknr, 'r')
        local a = fh:read(BLOCKSIZE)
        fh:close()

        print("_getblock|return:"..#a)
        if a and #a then
            data[i] = a
        end
    end
    return data[i] or empty_block
end,

write = function(self, path, buf, offset, obj)

    local entity = fs_meta[path]
    local data   = entity.contents
    local dirty  = {}
    local findx  = floor(offset/BLOCKSIZE)

    -- BLOCKSIZE matches ours + offset falls on the start: just assign
    if offset % BLOCKSIZE == 0 and #buf == BLOCKSIZE then
        data[findx]  = buf
        dirty[findx] = true
    else
        local lindx = floor((offset + #buf - 1)/BLOCKSIZE)

        -- fast and nice: same index, but substr() is needed
        if findx == lindx then
            local a = offset % BLOCKSIZE
            local b = a + #buf + 1

            data[findx]  = data[findx] or empty_block
            data[findx]  = substr(data[findx],0,a) .. buf .. substr(data[findx],b)

            dirty[findx] = true
        else
            -- simple checks don't match: multiple blocks need to be adjusted.
            -- I'll do that in 3 steps:

            -- start: will exist, as findx!=lindx
            local boffset = offset - findx*BLOCKSIZE
            local a,b = 0,BLOCKSIZE - boffset
            data[findx]  = substr(data[findx] or empty_block, 0, boffset) .. substr(buf, a, b)
            dirty[findx] = true

            -- middle: doesn't necessarily have to exist
            for i=findx+1,lindx-1 do
                a, b = b + 1, b + 1 + BLOCKSIZE
                data[i] = substr(buf, a, b)
                dirty[i] = true
            end

            -- end: maybe exist, as findx!=lindx, and not ending on blockboundary
            a, b = b + 1, b + 1 + BLOCKSIZE
            data[lindx]  = substr(buf, a, b) .. substr(data[lindx] or empty_block, b)
            dirty[lindx] = true

        end
    end

    -- rewrite all blocks to disk
    for i, _ in pairs(dirty) do
        dirty[i] = getnextblocknr()

        fh = io.open(self.datadir.."/"..dirty[i], 'w')
        fh:write(data[i])
        fh:close()
    end

    -- adjust the metadata in the journal
    for i, _ in pairs(dirty) do
        local size = entity.size > (offset + #buf) and entity.size or (offset + #buf)
        self:_setblock(path, i, dirty[i], size)
    end

    return #buf
end,

_setblock = function(self, path, i, bnr, size, ctime)
    local e = fs_meta[path]
    e.blockmap[i] = bnr
    e.size        = size
    e.ctime       = ctime
    e.mtime       = ctime
    block_nr      = bnr -- kindof 'dirty' but the journal will be correct
    return 0
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

    -- update meta information
    m.ctime = ctime
    m.mtime = ctime
    m.size  = size

    -- update contents
    local lindx = floor(size/BLOCKSIZE)
    local data  = m.contents
    local map   = m.blockmap
    for i=lindx+1,#data do
        data[i] = nil
        map[i]  = nil
    end
    data[lindx] = substr(data[lindx] or empty_block,0,size%BLOCKSIZE)

    return 0
end,

rename = function(self, from, to, ctime)

    -- FUSE handles paths, e.g. a file being moved to a directory: the 'to'
    -- becomes that target directory + "/" + basename(from).

    -- rename main node
    fs_meta[to]   = fs_meta[from]
    fs_meta[from] = nil

    -- rename both parent's references to the renamed entity
    local p,e

    -- 'to'
    p, e = to:splitpath()
    fs_meta[p].directorylist[e] = fs_meta[to]
    fs_meta[p].nlink = fs_meta[p].nlink + 1
    fs_meta[p].ctime = ctime
    fs_meta[p].mtime = ctime

    -- 'from'
    p,e = from:splitpath()
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
    local parent,file = to:splitpath()
    fs_meta[to] = new_meta(mk_mode(7,7,7) + S_IFLNK, cuid, cgid, ctime)
    fs_meta[to].nlink  = 1
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
        entity.nlink = entity.nlink + 1

        -- 'copy'
        fs_meta[to]  = fs_meta[from]

        -- update the TO parent: add entry + change meta
        local toparent,e = to:splitpath()
        fs_meta[toparent].directorylist[e] = fs_meta[to]
        fs_meta[toparent].ctime = ctime
        fs_meta[toparent].mtime = ctime
        
        return 0
    else
        return ENOENT
    end
end,

unlink = function(self, path, ctime)

    local entity = fs_meta[path]
    entity.nlink = entity.nlink - 1
    entity.ctime = ctime

    local p,e = path:splitpath()
    fs_meta[p].directorylist[e] = nil
    fs_meta[p].ctime = ctime
    fs_meta[p].mtime = ctime

    -- nifty huh ;-).. : decrease links to the entry + delete *this*
    -- reference from the tree and the meta, other references will see the
    -- decreased nlink from that

    fs_meta[path] = nil

    return 0
end,

mknod = function(self, path, mode, rdev, cuid, cgid, ctime)
    -- only called for non-symlinks, non-directories, non-files and links as
    -- those are handled by symlink, mkdir, create, link. This is called when
    -- mkfifo is used to make a named pipe for instance.
    --
    -- FIXME: support 'plain' mknod too: S_IFBLK and S_IFCHR
    fs_meta[path]         = new_meta(mode, cuid, cgid, ctime)
    fs_meta[path].nlink   = 1
    fs_meta[path].dev     = rdev

    local parent,file = path:splitpath()
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
--    local p = '/'
--    for dir in string.gmatch(path, "[^/]+") do
--        p = p .. dir
--        print("access():dirpart:"..dir..",p:"..p)
--        if fs_meta[p] then
--            if _bor(fs_meta[p].mode, mode) == 0 then
--                return EPERM
--            end
--        else
--            if _bor(mode, F_OK) then return ENOENT end
--        end
--    end

    return 0
end,

fsync = function(self, path, isdatasync, obj)
    return 0
end,

fsyncdir = function(self, path, isdatasync, obj)
    return 0
end,

fgetattr = function(self, path, obj)
    local x = obj.f
    print("fgetattr():"..x.mode..",".. x.ino..",".. x.dev..",".. x.nlink..",".. x.uid..",".. x.gid..",".. x.size..",".. x.atime..",".. x.mtime..",".. x.ctime)
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

destroy = function(self)
    self.meta_fh:close()
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
    local dir,file = path:splitpath()
    if #file > 255 then
        return ENAMETOOLONG
    end
    local x = fs_meta[path]
    if not x then
        return ENOENT, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    end 
    print("getattr():"..x.mode..",".. x.ino..",".. x.dev..",".. x.nlink..",".. x.uid..",".. x.gid..",".. x.size..",".. x.atime..",".. x.mtime..",".. x.ctime)
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

listxattr = function(self, path, size)
    if fs_meta[path] then
        local s = "\0"
        for k,v in pairs(fs_meta[path].xattr) do 
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
    if fs_meta[path] then
        fs_meta[path].xattr[name] = nil
        return 0
    else
        return ENOENT
    end
end,

setxattr = function(self, path, name, val, flags)
    if fs_meta[path] then
        fs_meta[path].xattr[name] = val
        return 0
    else
        return ENOENT
    end
end,

getxattr = function(self, path, name, size)
    if fs_meta[path] then
        return fs_meta[path].xattr[name] or "" --not found is empty string
    else
        return ENOENT, ""
    end
end,

statfs = function(self, path)
    local o = {bs=BLOCKSIZE,blocks=4096,bfree=1024,bavail=3072,bfiles=1024,bffree=1024}
    return 0, o.bs, o.blocks, o.bfree, o.bavail, o.bfiles, o.bffree
end,

serializemeta = function(self)
    local inode = {}
    local lines = {}
    local new_meta_fh = io.open(self.metafile..'.new', 'w')
    for k,e in pairs(fs_meta) do
        local prefix = 'fs_meta["'..k..'"]'
        if inode[e.ino] then
            -- just add a link
            new_meta_fh:write(prefix,' = fs_meta["',inode[e.ino],'"]\n')
        else
            inode[e.ino] = k

            -- metadata:xattr
            local xattr_str = {}
            local meta_str  = {}
            for x,v in pairs(e.xattr) do
                if type(v) == 'boolean' and v == true then
                    arrayadd(xattr_str, '["'..x..'"]=true')
                    break
                end
                if type(v) == 'boolean' and v == false then
                    arrayadd(xattr_str, '["'..x..'"]=false')
                    break
                end
                arrayadd(xattr_str, '["'..x..'"]='..format('%q',v))
            end
            arrayadd(meta_str, 'xattr={'..concat(xattr_str, ',')..'}')

            -- regular values + symlink target
            for key, value in pairs(e) do
                if type(value) == "number" then
                    arrayadd(meta_str, key..' = '..value)
                elseif type(value) == "string" then
                    arrayadd(meta_str, key..' = '..format("%q", value))
                end
            end

            new_meta_fh:write(prefix,' = {', concat(meta_str, ","),'}\n')


            -- directorylist
            if e.directorylist then
                local t = {}
                for d, _ in pairs(e.directorylist) do
                    arrayadd(t, '["'..d..'"]=true')
                end
                new_meta_fh:write(prefix,'.directorylist = {',concat(t, ','),'}\n')
            end

            -- contents
            if e.contents then
                new_meta_fh:write(prefix,'.contents = {}\n')
                for i, data in pairs(e.contents) do
                    new_meta_fh:write(prefix,'.contents[',i,'] = ',format("%q", data),"\n")
                end
            end
        
            
        end
    end
    new_meta_fh:close()
    return lines
end,

writemetajournalentry = function(self, prefix, arglist)

    -- persistency: make the lua function call
    local o = {}
    for i,w in ipairs(arglist) do
        if type(arglist[i]) == "number" then
            o[i] = arglist[i]
        elseif type(arglist[i]) == "string" then
            o[i] = format("%q", arglist[i])
        end
    end

    -- ....and save it to the metafile
    self.meta_fh:write(prefix, concat(o,","), ")\n")
    if debug then
        self.meta_fh:flush()
    end

    return 1
end,


metafile = "/home/tim/tmp/fs/test.lua",
datadir  = "/home/tim/tmp/fs/luafs-data"

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
    '-oreaddir_ino'
}

for i,w in ipairs(fuse_options) do
    arrayadd(options, w)
end

-- check the mountpoint
require "lfs"
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
say = print
if debug == 0 then 
    function print() end
end

for k, f in pairs(luafs) do
    if type(f) == 'function' then
        luafs[k] = function(self,...) 
            
            -- debug?
            if debug then
                local d = {}
                for i,v in ipairs(arg) do
                    if type(v) ~= 'table' then 
                        d[i] = v 
                    else
                        d[i] = "<ref>"
                    end
                end
                print("function:"..k.."(),args:"..concat(d, ","))
            end
            -- really call the function
            return f(self, unpack(arg))
        end
    end
end

for i,w in ipairs(options) do
    print("option:"..w)
end

--
-- open that state for further updates, create if it doesn't exist
--
-- FIXME: make a nice close upon destroy (umount and signals)
-- 
local meta_fh = io.open(luafs.metafile, "r")
if not meta_fh then
    meta_fh = io.open(luafs.metafile, "w")
else
    --
    -- read in the state the filesystem was at umount, this *must* be done
    -- *before* the update change methods are made a little bit further
    --
    for l in meta_fh:lines() do
        assert(loadstring(l))()
    end
    say("done reading metadata from "..luafs.metafile) 
end
meta_fh:close()
meta_fh = io.open(luafs.metafile, "a+")
luafs.meta_fh = meta_fh

-- make the datadir
lfs.mkdir(luafs.datadir)

--
-- loop over all the functions and add a wrapper to write meta data
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
    local fusemethod  = luafs[k]
    local prefix      = "luafs:"..k.."("
    local meta_fh     = luafs.meta_fh
    luafs[k] = function(self,...) 

        -- always add the time at the end, methods that change the metastate
        -- usually need this to adjust the ctime
        arg[#arg+1] = time()

        self:writemetajournalentry(prefix, arg)
        
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
    local fusemethod  = luafs[k]
    local fusecontext = fuse.context
    luafs[k] = function(self,...) 
        
        arg[#arg+1], arg[#arg+2] = fusecontext()

        -- really call the function
        return fusemethod(self, unpack(arg))
    end
end


--
-- start the main fuse loop
--
print("main()")
fuse.main(luafs, options)
