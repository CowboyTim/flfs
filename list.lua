
local P = {}

local sort = table.sort
local push = table.insert
local join = table.concat
local pop  = table.remove

function P:tostring()
    local l = {}
    local t = {}
    local bl = rawget(self, '_original')
    for i, v in ipairs(bl.indx) do
        --print("ts:"..tostring(i)..","..tostring(v))
        push(t, '['..v..']='..bl[v])
        local b = bl[v]
        push(l, '['..b..']='..bl.list[b])
    end
    local k = {}
    push(k, 'list={'..join(l, ',')..'}')
    push(k, 'map={'..join(t, ',')..'}')
    return 'list:new{'..join(k, ',')..'}'
end

function P:new(data)
    --print("LIST:new()")

    -- new list
    local bl = data or {}

    -- add the index index
    local index = {}
    local map   = bl.map or {}
    for n, v in pairs(map) do
        bl[n] = map[n]
        push(index, n) 
    end
    sort(index)
    bl.indx = index
    bl.list = bl.list or {}

    -- set the correct metatable 'tie'
    local _bl = bl
    bl = {_original = _bl}
    local mt = {
        __index = function(self, a)
            --print("__index:"..a)
            local r = P.match(_bl,a)
            --print("__index returns:"..a..",r:"..tostring(r))
            return r
            --return P.match(_bl,a)
        end,

        __newindex = function(self, a, v)
            --print("__newindex:"..a..",v:"..v)
            return P.insert(_bl, a, v)
        end,
    }
    setmetatable(bl, mt)
    return bl
end

function P:merge(blocklist)
    --print("merge()")
    local thisbl    = rawget(self,      '_original')
    local otherbl   = rawget(blocklist, '_original')
    for _,i in ipairs(otherbl.indx) do
        local m = otherbl[i]
        --print("i:"..tostring(i)..",m:"..m..",l:"..otherbl.list[m])
        thisbl[i]      = m
        thisbl.list[m] = otherbl.list[m]
        push(thisbl.indx, i)
    end
    return self
end

function P:replacepart(blocklist)
    local thisbl  = rawget(self,      '_original')
    local otherbl = rawget(blocklist, '_original')

    -- self is empty?
    local index = thisbl.indx
    if #index == 0 then
        P.merge(self, blocklist)
        return nil
    end

    -- start of the replacement
    local otherindx = otherbl.indx
    local si = otherindx[1]

    -- end of the replacement
    local li = otherindx[#(otherindx)]
    li = li + (otherbl.list[otherbl[li]] - otherbl[li])
    --print("si:"..tostring(si)..",li:"..tostring(li)..",otherbl[si]:"..P.tostring(blocklist))

    -- fast bail out for 1 sized
    if li == si then
        local b = P.insert(thisbl, si, otherbl[si])
        if b then
            return {[b]=b}
        end
        return nil
    end

    -- too big request? -> just merge and return nil
    local list = thisbl.list
    local last_index       = index[#index]
    local last_start_block = self[index[#index]]
    if si > last_index + list[last_start_block] - last_start_block then
        P.merge(self, blocklist)
        return nil
    end 

    -- complex: subtract (and return it) + merge
    local result = P.truncate(self, si, li)
    P.merge(self, blocklist)
    P._canonicalize(thisbl)
    return result
end

function P:truncate(v, e)
    local bl    = rawget(self, '_original')
    local index = bl.indx
    local list  = bl.list

    local remainder = {}
 
    local delete = false
    local newindex = {}
    for j=1,#index do
        local low_bi = index[j]
        local low_bn = bl[low_bi]
        local high = low_bi + (list[low_bn] - low_bn)
        if v >= low_bi and v <= high  then
            if v == low_bi then
                remainder[low_bn] = list[low_bn]
                list[low_bn] = nil
                bl[low_bi]   = nil
            else
                local old_list = list[low_bn]
                local new_low_bn = low_bn + (v - low_bi)
                list[low_bn] = new_low_bn - 1
                push(newindex, low_bi)
                remainder[new_low_bn] = old_list
            end
            delete = true
        elseif e and e >= low_bi and e <= high  then
            if e == low_bi then
                list[low_bn] = nil
                bl[low_bi]   = nil
            else
                local old_list = list[low_bn]
                list[low_bn]   = nil
                bl[low_bi]     = nil
                low_bn = low_bn + (e - low_bi) + 1
                low_bi = e + 1
                bl[low_bi] = low_bn
                list[low_bn] = old_list
                push(newindex, low_bi)
            end
            delete = false
            remainder[low_bn] = low_bn + (e - low_bi)
        elseif delete then
            remainder[low_bn] = list[low_bn]
            list[low_bn] = nil
            bl[low_bi]   = nil
        else
            push(newindex, index[j])
        end
    end
    bl.indx = newindex
    return remainder
end

function P:match(v)

    local index = self.indx
    if #index == 0 then
        return nil
    end

    -- first: plain hash check
    local l = self[v]
    if l then 
        return l 
    end

    local list = self.list
    local last_index       = index[#index]
    local last_start_block = self[index[#index]]
    
    -- too big request? -> return nil
    if v > last_index + list[last_start_block] - last_start_block then
        return nil
    end 
    
    -- second: sorted
    for j=1,#index do
        last_index = index[j]
        last_start_block = self[last_index]
        -- FIXME: implement faster stop in case of non match
        if v >= last_index and v <= last_index + (list[last_start_block] - last_start_block) then
            return last_start_block + (v - last_index)
        end
    end

    return nil
end

function P:insert(i, v)

    --print("insert:i:"..i..",v:"..v..":"..P.tostring({_original=self}))

    local index = self.indx
    local list  = self.list

    if #index == 0 then
        -- empty list: add the entry
        self[i] = v
        list[v] = v
        push(index, i)
        return nil
    end

    local list_i = list[self[i]]

    local old_block_nr

    if list_i then
        old_block_nr = self[i]
        if list_i == self[i] then
            -- item exists and is size 1; just update
            --print("hash append")
            list[self[i]] = nil
            self[i] = v
            list[v] = v
            -- FIXME: implement fast canonicalize here
        else
            -- at the start. NOTE: i+1 will not exist, as size > 1
            --print("start append")
            local n = i+1
            self[n]         = self[i] + 1
            list[self[n]]   = list_i
            push(index, n)
            self[i]         = v
            list[v]         = v
            -- FIXME: implement fast canonicalize here
        end
    else
        local last_index = index[#index]
        local last_block = self[last_index]
        local next_block = 1 + list[last_block]
        local next_index = last_index + next_block - last_block
        if i == next_index and v == next_block then
            -- plain append
            --print("plain append")
            list[last_block] = v
            return nil
        elseif i >= next_index then
            -- sparse append: just add
            --print("sparse append")
            self[i] = v
            list[v] = v
            push(index, i)
            return nil

        else
            --print("middle insert")
        
            -- item didn't exist directly: search for the base
            for j=1,#index do
                -- FIXME: implement faster stop in case of non match
                local a = index[j]
                list_i  = list[self[a]]
                --print("a:"..a..",i:"..i..",list[a]:"..list_i..",self:"..self[a])
                if i >= a and i <= a + (list_i - self[a]) then
                    old_block_nr = self[a] + (i - a)
                    if a + list_i - self[a]  == i then
                        --print("middle insert:at last")
                        -- entirely at the end: just add and shrink
                        self[i] = v
                        list[v] = v
                        list[self[a]] = list_i - 1
                        push(index, i)
                        -- FIXME: implement fast canonicalize here
                    else
                        --print("middle insert:not at last")
                        -- in the middle
                        list[self[a]] = self[a] + (i - a) - 1
                        self[i] = v
                        list[v] = v
                        push(index, i)
                        self[i+1] = self[a] + (i - a) + 1
                        list[self[i+1]] = list_i
                        push(index, i+1)
                        -- FIXME: implement fast canonicalize here
                    end
                    break
                end
            end
        end
    end

    P._canonicalize(self)

    return old_block_nr
end

function P:_canonicalize()
    --print("_canonicalize:"..P.tostring({_original = self}))
    
    local index = self.indx
    if #index <= 1 then
        return
    end
    local list = self.list

    local newindex = {}
    sort(index)
    push(newindex, index[1])
    local l = 1
    for i=2,#index do
        local previous_index       = index[l]
        --print("previous_index:"..tostring(previous_index)..",l:"..l)
        local previous_block       = list[self[previous_index]]
        local current_index        = index[i]
        local current_block_start  = self[index[i]]
        if      previous_block + 1       == current_block_start
            and current_index - previous_index 
                                         == previous_block - self[previous_index] + 1
        then
            list[self[previous_index]] = list[current_block_start]
            list[current_block_start]  = nil
            self[current_index]        = nil
        else 
            push(newindex, current_index)
            l = i
        end
    end

    self.indx = newindex
end


if _REQUIREDNAME == nil then
    list = P
else
    _G[_REQUIREDNAME] = P
end


return list
