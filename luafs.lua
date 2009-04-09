#!/usr/bin/env lua

local fuse = require 'fuse'

local S_WID    = 1 --world
local S_GID    = 2^3 --group
local S_UID    = 2^6 --owner
local S_SID    = 2^9 --sticky bits etc.
local S_IFIFO  = 1*2^12
local S_IFCHR  = 2*2^12
local S_IFDIR  = 4*2^12
local S_IFBLK  = 6*2^12
local S_IFREG  = 2^15
local S_IFLNK  = S_IFREG + S_IFCHR
local ENOENT   = -2
local EEXISTS  = -17
local ENOSYS   = -38
local ENOATTR  = -516
local ENOTSUPP = -524

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

--local function print () end


local ff = 2^32 - 1
local function _bnot(a) return ff - a end

local function _band(a,b) return ((a+b) - _bxor(a,b))/2 end

local function _bor(a,b) return ff - _band(ff - a, ff - b) end

local function set_bits(mode, bits)
    return _bor(mode, bits)
end

function string:splitpath() 
    local dir,file = self:match("(.-)([^:/\\]*)$") 
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

local uid,gid,pid,puid,pgid = fuse.context()

function new_meta(mymode)
    local t = os.time()
    return {
        xattr = {[-1] = true},
        mode  = mymode,
        ino   = 0,
        dev   = 0,
        nlink = 2,
        uid   = puid,
        gid   = pgid,
        size  = 0,
        atime = t,
        mtime = t,
        ctime = t
    }
end

local fs_meta = {
    ["/"] = new_meta(mk_mode(7,5,5) + S_IFDIR)
}
fs_meta["/"].directorylist = {}

local luafs   = {

rmdir = function(self, path)
    print("rmdir():"..path)
    if next(fs_meta[path].directorylist) then
        return EEXISTS
    end

    local parent,dir = path:splitpath()
    fs_meta[parent].nlink = fs_meta[parent].nlink - 1
    fs_meta[parent].directorylist[dir] = nil
    fs_meta[path] = nil
    return 0
end,

mkdir = function(self, path, mode)
    print('mkdir():'..path)
    local parent,subdir = path:splitpath()
    print("parentdir:"..parent)
    fs_meta[path] = new_meta(mode + S_IFDIR)
    fs_meta[path].directorylist = {}
    fs_meta[parent].nlink = fs_meta[parent].nlink + 1
    fs_meta[parent].directorylist[subdir] = fs_meta[path]

    print("made dir, mode:"..fs_meta[path].mode)
    return 0
end,

opendir = function(self, path)
    print("opendir():"..path)
    return 0, { t=fs_meta[path].directorylist, k=nil }
end,

readdir = function(self, path, offset, dir_fh)
    print("readdir():"..path..",offset:"..offset)
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
    return 0, {{d_name=dir_ent, ino=n.ino, d_type=n.mode, offset=offset + 1}}
end,

releasedir = function(self, path, dirent)
    print("releasedir():"..path)
    dirent.k = nil
    dirent.t = nil
    -- eventually the last reference to it will disappear
    return 0
end,

open = function(self, path, mode)
    print("open():"..path)
    local entity = fs_meta[path]
    if entity then
        return 0, { f=entity }
    else
        return ENOENT
    end
end,

create = function(self, path, mode, flag)
    print("create():"..path)
    local parent,file = path:splitpath()
    fs_meta[path] = new_meta(set_bits(mode, S_IFREG))
    fs_meta[path].nlink = 1
    fs_meta[parent].directorylist[file] = fs_meta[path]
    return 0, { f=fs_meta[path] }
end,

read = function(self, path, size, offset, obj)
    print("read():"..path)
    return 0, nil
end,

write = function(self, path, buf, offset, obj)
    print("write():"..path)
    return nil
end,

release = function(self, path, obj)
    print("release():"..path)
    obj.f = nil
    return 0
end,

flush = function(self, path, obj)
    print("flush()")
    return 0
end,

rename = function(self, from, to)
    print("rename():from:"..from..",to:"..to)
    if from == to then return 0 end

    local entity = fs_meta[from]
    if entity then
        -- rename main node
        fs_meta[to]   = fs_meta[from]
        fs_meta[from] = nil

        -- rename both parent's references to us
        local p,e = to:splitpath()
        fs_meta[p].directorylist[e] = fs_meta[to]
        p,e = from:splitpath()
        fs_meta[p].directorylist[e] = nil

        -- rename all decendants, maybe not such a good idea to use this
        -- mechanism, but don't forget, how many times does one rename e.g.
        -- /usr and such.. ;-). for a plain file (or empty subdir), this is for
        -- isn't even executed (looped actually)
        --
        for sub in pairs(fs_meta[to].directorylist or {}) do
            ts= to   .. "/" .. sub
            fs= from .. "/" .. sub
            print("r:"..sub..",to:"..ts..",from:"..fs)
            fs_meta[ts] = fs_meta[fs]
            fs_meta[fs] = nil
        end

        return 0
    else
        return ENOENT
    end
end,

symlink = function(self, from, to)
    -- 'from' isn't used,.. that can be even from a seperate filesystem, e.g.
    -- when someone makes a symlink on this filesystem...
    print("symlink():"..from..",to:"..to)
    local parent,file = to:splitpath()
    fs_meta[to] = new_meta(mk_mode(7,7,7) + S_IFLNK)
    fs_meta[to].nlink  = 1
    fs_meta[to].target = from
    fs_meta[parent].directorylist[file] = fs_meta[to]
    return 0
end,

readlink = function(self, path)
    print("readlink():"..path)
    local entity = fs_meta[path]
    if entity then
        return 0, fs_meta[path].target
    else
        return ENOENT
    end
end,

link = function(self, from, to)
    print("link():"..from..",to:"..to)
    local entity = fs_meta[from]
    if entity then
        entity.nlink = entity.nlink + 1
        fs_meta[to] = fs_meta[from]

        local toparent,e = to:splitpath()
        fs_meta[toparent].directorylist[e] = fs_meta[to]
        
        return 0
    else
        return ENOENT
    end
end,

unlink = function(self, path)
    print("unlink():"..path)

    local entity = fs_meta[path]
    entity.nlink = entity.nlink - 1

    local p,e = path:splitpath()
    fs_meta[p].directorylist[e] = nil

    -- nifty huh ;-).. : decrease links to the entry + delete *this*
    -- reference from the tree and the meta, other references will see the
    -- decreased nlink from that

    fs_meta[path] = nil

    return 0
end,

mknod = function(self, path, mode, rdev)
    -- only called for non-symlinks, non-directories, non-files and links as
    -- those are handled by symlink, mkdir, create, link. This is called when
    -- mkfifo is used to make a named pipe for instance.
    --
    -- FIXME: support 'plain' mknod too: S_IFBLK and S_IFCHR
    print("mknod():"..path)
    fs_meta[path]         = new_meta(mode)
    fs_meta[path].nlink   = 1
    fs_meta[path].dev     = rdev
    local parent,file = path:splitpath()
    fs_meta[parent].directorylist[file] = fs_meta[path]
    return 0
end,

chown = function(self, path, uid, gid)
    print("chown():"..path..",uid:"..uid,",gid:"..gid)
    local entity = fs_meta[path] 
    if entity then
        entity.uid = uid
        entity.gid = gid
        return 0
    else
        return ENOENT
    end
end,

chmod = function(self, path, mode)
    print("chmod():"..path..",mode:"..mode)
    local entity = fs_meta[path] 
    if entity then
        entity.mode = mode
        return 0
    else
        return ENOENT
    end
end,

utime = function(self, path, atime, mtime)
    print("utime()")
    local entity = fs_meta[path] 
    if entity then
        entity.atime = atime
        entity.mtime = mtime
        return 0
    else
        return ENOENT
    end
end,

ftruncate = function(self, path, size, obj)
    print("ftruncate()")
    local old_size = obj.meta.size
    obj.meta.size = size
    clear_buffer(obj, floor(size/mem_block_size), floor(old_size/mem_block_size))
    return 0
end,

truncate = function(self, path, size)
    print("truncate()")
    local entity = fs_meta[path]
    if entity then 
        -- FIXME: use the size parameter and implement something correct
        fs_data[path] = nil
    else
        return ENOENT
    end
end,

access = function(self, path)
    print("access()")
    -- FIXME: nop?! see man access, why do I need this?! 
    return 0
end,

fsync = function(self, path, isdatasync, obj)
    print("fsync()")
    return 0
end,

fsyncdir = function(self, path, isdatasync, obj)
    print("fsyncdir()")
    return 0
end,

fgetattr = function(self, path, obj)
    print("fgetattr():"..path)
    local x = obj.f
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,


getattr = function(self, path)
    print("getattr():"..path)
    local x = fs_meta[path]
    if not x then
        return ENOENT
    end 
    return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,

listxattr = function(self, path, size)
    print("listxattr()")
    local xa = fs_meta[path].xattr
    if xa then
        s = "\0"
        for k,v in pairs(xa) do 
            if type(v) == "string" then
                s = v .. "\0" .. s
            end
        end
        return 0, s
    else
        return ENOENT
    end
end,

removexattr = function(self, path, name)
    print("removexattr()")
    local xa = fs_meta[path].xattr
    if xa then
        xa[name] = nil
        return 0
    else
        return ENOENT
    end
end,

setxattr = function(self, path, name, val, flags)
    print("setxattr()")
    local xa = fs_meta[path].xattr
    if xa then
        xa[name] = val
        return 0
    else
        return ENOENT
    end
end,

getxattr = function(self, path, name, size)
    print("getxattr()")
    local xa = fs_meta[path].xattr
    if xa then
        return 0, xa[name] or "" --not found is empty string
    else
        return ENOENT
    end
end,

statfs = function(self, path)
    print("statfs()")
    local o = {bs=1024,blocks=4096,bfree=1024,bavail=3072,bfiles=1024,bffree=1024}
    return 0, o.bs, o.blocks, o.bfree, o.bavail, o.bfiles, o.bffree
end
}

fuse_opt = { 'luafs', 'mnt', '-f', '-s', '-oallow_other'}

if select('#', ...) < 2 then
    print(string.format("Usage: %s <fsname> <mount point> [fuse mount options]", arg[0]))
    os.exit(1)
end

print("main()")
fuse.main(luafs, {...})
