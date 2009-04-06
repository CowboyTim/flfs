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

function new_meta(mode, otype, mypath)
    return {
        xattr = {[-1] = true},
        mode  = mode + otype,
        ino   = 0,
        dev   = 0,
        nlink = 2,
        uid   = puid,
        gid   = pgid,
        size  = 0,
        atime = os.time(),
        mtime = os.time(),
        ctime = os.time(),
        path  = mypath
    }
end

local fs_meta = {
    ["/"] = new_meta(mk_mode(7,5,5), S_IFDIR, '/')
}
local fs_tree = {
    ["/"] = {}
}

local luafs   = {

rmdir = function(self, path)
    print("rmdir():"..path..",n:".. # fs_tree[path])
    if next(fs_tree[path]) then
        return EEXISTS
    end

    local parent,dir = path:splitpath()
    fs_meta[parent].nlink = fs_meta[parent].nlink - 1
    fs_tree[parent][dir] = nil
    fs_meta[path] = nil
    fs_tree[path] = nil
    return 0
end,

mkdir = function(self, path, mode)
    print('mkdir():'..path)
    local parent,subdir = path:splitpath()
    print("parentdir:"..parent)
    fs_meta[parent].nlink = fs_meta[parent].nlink + 1
    fs_meta[path] = new_meta(mode,S_IFDIR,path)

    fs_tree[path] = {}
    fs_tree[parent][subdir] = fs_meta[path]

    print("made dir, mode:"..fs_meta[path].mode)
    return 0
end,

opendir = function(self, path)
    print("opendir():"..path)
    return 0, { t=fs_tree[path], k=nil }
end,

readdir = function(self, path, offset, dir_fh)
    print("readdir():"..path..",offset:"..offset)
    local dir_ent, dir_ent_meta = next(dir_fh.t, dir_fh.k)
    if dir_ent == nil then
        return 0, {}
    end
    dir_fh.k = dir_ent
    print("readdir(),v:"..dir_ent..",meta_path:"..dir_ent_meta.path)
    local n = fs_meta[dir_ent_meta.path]
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
end,

create = function(self, path, mode, flag)
    print("create():"..path)
    local parent,file = path:splitpath()
    fs_meta[path] = new_meta(mode, S_IFREG, path)
    fs_tree[parent][file] = fs_meta[path]
    return 0, nil
end,

read = function(self, path, size, offset, obj)
    print("read()")
    return 0, nil
end,

write = function(self, path, buf, offset, obj)
    print("write()")
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

readlink = function(self, path)
    print("readlink()")
    local entity = fs_meta[from]
    if entity then
        -- TODO: implement!
        return 0
    else
        return ENOENT
    end
end,

symlink = function(self, from, to)
    print("symlink()")
    local entity = fs_meta[from]
    if entity then
        -- TODO: implement!
        return 0
    else
        return ENOENT
    end
end,

rename = function(self, from, to)
    print("rename():from:"..from..",to:"..to)
    if from == to then return 0 end

    local entity = fs_meta[from]
    if entity then
        -- rename main node
        fs_meta[to]   = fs_meta[from]
        fs_tree[to]   = fs_tree[from]
        fs_meta[from] = nil
        fs_tree[from] = nil

        fs_meta[to].path = to

        -- rename both parent's references to us
        local p,e = to:splitpath()
        fs_tree[p][e] = fs_meta[to]
        p,e = from:splitpath()
        fs_tree[p][e] = nil

        -- rename all decendants, maybe not such a good idea to use this
        -- mechanism, but don't forget, how many times does one rename e.g.
        -- /usr and such.. ;-). for a plain file (or empty subdir), this is for
        -- isn't even executed (looped actually)
        --
        for sub in pairs(fs_tree[to]) do
            ts= to   .. "/" .. sub
            fs= from .. "/" .. sub
            print("r:"..sub..",to:"..ts..",from:"..fs)
            fs_tree[ts] = fs_tree[fs]
            fs_meta[ts] = fs_meta[fs]
            fs_tree[fs] = nil
            fs_meta[fs] = nil
        end

        return 0
    else
        return ENOENT
    end
end,

link = function(self, from, to)
    print("link()")
    local entity = fs_meta[from]
    if entity then
        entity.nlink = entity.nlink + 1
        fs_meta[to] = fs_meta[from]
        fs_tree[to] = fs_tree[from]
        return 0
    else
        return ENOENT
    end
end,

unlink = function(self, path)
    print("unlink():"..path)
    local entity = fs_meta[path]
    if entity then

        entity.nlink = entity.nlink - 1

        -- nifty huh ;-).. : decrease links to the entry + delete *this*
        -- reference from the tree and the meta, other references will see the
        -- decreased nlink from that

        fs_meta[path] = nil
        fs_tree[path] = nil
        return 0
    else
        return ENOENT
    end
end,

mknod = function(self, path, mode, rdev)
    -- only called for non-symlinks, non-directories, non-files and links.
    -- Those are handled by symlink, mkdir, create, link
    print("mknod():"..path)
    return 0, nil
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
    local entity = fs_tree[path]
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
    print("fgetattr()")
    --return 0, x.mode, x.ino, x.dev, x.nlink, x.uid, x.gid, x.size, x.atime, x.mtime, x.ctime    
end,


getattr = function(self, path)
    print("getattr():"..path)
    local entity = fs_meta[path]
    if not entity then
        return ENOENT
    end 
    return 0, entity.mode, entity.ino, entity.dev, entity.nlink, entity.uid, entity.gid, entity.size, entity.atime, entity.mtime, entity.ctime    
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
