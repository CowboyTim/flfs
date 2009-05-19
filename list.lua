
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
    return join(k, ',')
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

function P:truncate(v)
    local bl    = rawget(self, '_original')
    local index = bl.indx
    local list  = bl.list
 
    -- second: sorted
    local delete = false
    local newindex = {}
    for j=1,#index do
        local low_bi = index[j]
        local low_bn = bl[low_bi]
        local high = low_bi + (list[low_bn] - low_bn)
        if v >= low_bi and v <= high  then
            if v == low_bi then
                list[low_bn] = nil
                bl[low_bi]   = nil
            else
                list[low_bn] = low_bn + (v - low_bi) - 1
                push(newindex, index[j])
                delete = true
            end
        elseif delete then
            list[low_bn] = nil
            bl[low_bi]   = nil
        else
            push(newindex, index[j])
        end
    end
    bl.indx = newindex
    return
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

function P:getlast()
    local bl = rawget(self, '_original')
    local index = bl.indx
    if #index == 0 then
        return nil
    end
    
    local block = nil
    local list = bl.list
    local last_startblock = bl[index[#index]]
    if list[last_startblock] == last_startblock then
        list[last_startblock] = nil
        bl[index[#index]]   = nil
        pop(index)
        block = last_startblock
    else
        block = list[last_startblock]
        list[last_startblock] = list[last_startblock] - 1
    end

    return block
end

function pairsByKeys (t, f)
  local a = {}
  for n in pairs(t) do 
        if type(n) == 'number' then
            push(a, n) 
        end
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

function P:mergetofreelist(b)
    local self_a  = rawget(self, '_original')
    local self_b  = rawget(b,'_original')
    --print("merge:"..P.tostring(self)..",b:"..P.tostring(b))
    local list_a  = self_a.list
    local list_b  = self_b.list
    for i,v in pairs(list_b) do
        list_a[i] = v
    end
    
    --print("before cc:"..P.tostring({_original=self}))
    local newlist = {}
    local last = nil
    local last_index = nil
    for i,v in pairsByKeys(list_a) do
        --print("i:"..i..",v:"..v..",last:"..tostring(last))
        if not last then
            newlist[i] = v
        else
            if last + 1 == i then
                newlist[last_index] = v
            else
                newlist[i] = v
            end
        end
        last = v
        last_index = i
    end
    local newself = {}
    local m = 0
    for i,v in pairs(newlist) do
        --print("i:"..i..",r:"..v..",m:"..m)
        newself[m] = i
        m = m + (v - i) + 1
    end
    return P.new({}, {["map"]=newself, ["list"]=newlist})
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
        return
    end

    local list_i = list[self[i]]

    if list_i then
        if list_i == self[i] then
            -- item exists and is size 1; just update
            --print("hash append")
            list[self[i]] = nil
            self[i] = v
            list[v] = v
        else
            -- at the start. NOTE: i+1 will not exist, as size > 1
            --print("start append")
            local n = i+1
            self[n]         = self[i] + 1
            list[self[n]]   = list_i
            push(index, n)
            self[i]         = v
            list[v]         = v
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
            return
        elseif i >= next_index and v ~= next_block then
            -- sparse append: just add
            --print("sparse append")
            self[i] = v
            list[v] = v
            push(index, i)
            return

        else
            --print("middle insert")
        
            -- item didn't exist directly: search for the base
            for j=1,#index do
                -- FIXME: implement faster stop in case of non match
                local a = index[j]
                list_i  = list[self[a]]
                --print("a:"..a..",i:"..i..",list[a]:"..list_i..",self:"..self[a])
                if i >= a and i <= a + (list_i - self[a]) then
                    if a + list_i - self[a]  == i then
                        --print("middle insert:at last")
                        -- entirely at the end: just add and shrink
                        self[i] = v
                        list[v] = v
                        list[self[a]] = list_i - 1
                        push(index, i)
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
                    end
                    break
                end
            end
        end
    end

    P._canonicalize(self)

    return
end

function P:_canonicalize()
    --print("_canonicalize:"..P.tostring({_original = self}))
    
    local index = self.indx
    if #index <= 1 then
        return
    end
    local list  = self.list

    local newindex = {}
    sort(index)
    push(newindex, index[1])
    local l = 1
    for i=2,#index do
        --print("iaaaaaaaaaaaaaaaaaaaaaaa:"..i)
        local previous_index       = index[l]
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
