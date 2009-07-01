local P = {}

local sort     = table.sort
local push     = table.insert
local join     = table.concat
local pop      = table.remove
local remove   = table.remove

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

function P:tostring()
    local t = {}
    push(t, 'freelist:new{freelist={')
    for i, v in pairs(self.freelist) do
        push(t, '['..i..']='..v..',')
    end
    push(t, '},stridemap={')
    for i, v in pairs(self.stridemap or {}) do
        push(t, '['..i..']={'..join(v,',')..'},')
    end
    push(t, '},stridesizeindex={')
    push(t, join(self.stridesizeindex, ','))
    push(t, '}}')
    return join(t, '')
end

function P:new(blocklist)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    self.freelist        = {}
    self.stridemap       = {}
    self.stridesizeindex = {}

    o:add(blocklist)

    return o
end

function P:add(blocklist)
    if not blocklist then 
        return  
    end
    local freelist = self.freelist
    for i,b in pairs(blocklist) do
        print("addtofreelist:i:"..i..",b:"..b)
        freelist[i] = b
    end

    -- FIXME: almost impossible to do this each add(), certainly in the case
    -- where the freelist contains lot's of entries.
    --
    -- as the freelist is allready sorted (or can be kept sorted with a
    -- seperate index, we can intelligently merge the new blocklist. This will
    -- be a lot faster than the full re-sort.
    self:canonicalize_freelist(freelist)

    return
end

function P:getnextstride(stride)
    local freelist = self.freelist
    if not next(freelist) then
        return nil
    end
    local stridemap = self.stridemap
    local stridesizeindex = self.stridesizeindex
    if stridemap[stride] then
        local s = pop(stridemap[stride])
        freelist[s] = nil
        if #(stridemap[stride]) == 0 then
            stridemap[stride] = nil
            -- FIXME: implement better search
            for i,v in ipairs(stridesizeindex) do
                if stride == v then
                    remove(stridesizeindex, i)
                    break
                end
            end
        end
        return s
    end

    -- no exact match found: take a bigger stride and chop it up
    -- FIXME: implement better search
    for i,v in ipairs(stridesizeindex) do
        if stride <= v then
            local s = pop(stridemap[v])
            if #(stridemap[v]) == 0 then
                stridemap[v] = nil
                stridesizeindex[i] = stridesizeindex[i] - stride
            end
            local e = freelist[s]
            freelist[s] = nil

            -- FIXME: intelligent insert would speed up
            self:add({[s+1]=e})
            return s
        end
    end

    return nil
end

function P:canonicalize_freelist(freelist)

    -- find the stridemap: sort freelist to find the grouping per size of free
    -- strides
    local stridemap = {}
    local last
    for i,v in pairsByKeys(freelist) do
        if not last then
            last = i
        else
            if i == freelist[last] + 1 then
                freelist[last] = freelist[i]
                freelist[i]    = nil
            else
                local s = freelist[last] - last + 1
                if not stridemap[s] then
                    stridemap[s] = {}
                end
                push(stridemap[s],last)
                last = i
            end
        end
    end
    if last then
        local s = freelist[last] - last + 1
        if not stridemap[s] then
            stridemap[s] = {}
        end
        push(stridemap[s],last)
    end

    -- fix up the strideindex: sort the stridemap for this, this is a smaller
    -- array to sort of course, as the array is in fact the key-index, which is
    -- 'limited' in the number of possibilities: 1k, 2k, 3k, .. 256k, would
    -- mean 256 different ones.
    local stridesizeindex = {}
    local k = 1
    for i,v in pairsByKeys(stridemap) do
        push(stridesizeindex,i)
        k = k + 1
    end
    self.stridemap       = stridemap
    self.stridesizeindex = stridesizeindex
end

local freelist
if _REQUIREDNAME == nil then
    freelist = P
else
    _G[_REQUIREDNAME] = P
end


return freelist