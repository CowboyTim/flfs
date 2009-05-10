
local P = {}

local sort = table.sort
local push = table.insert
local join = table.concat

function P:tostring()
    local l = {}
    local t = {}
    local list = self._list
    for i, v in ipairs(list.indx) do
        push(t, '['..v..']='..list[v])
        push(l, '['..i..']='..v)
    end
    local k = {}
    push(k, 'max='..list.max)
    push(k, 'indx={'..join(l, ',')..'}')
    push(k, 'map={'..join(t, ',')..'}')
    return join(k, ',')
end

function P:new(data)
    print("LIST:new()")

    -- new list
    local bl = {}

    -- add the index/max index
    local index = {}
    local map   = data and data.map  or {}
    local max   = data and data.max  or 0
    for n, v in pairs(map) do
        bl[n] = v
        push(index, n) 
        max = max > n and max or n
    end
    sort(index)
    bl.indx  = index
    bl.max   = max

    -- set the correct metatable 'tie'
    local _bl = bl
    bl = {_list = _bl}
    local mt = {
        __index = function(self, a)
            print("__index:"..a)
            local r = P.match(_bl,a)
            print("__index returns:"..a..",r:"..tostring(r))
            return r
        end,

        __newindex = function(self, a, v)
            print("__newindex:"..a..",v:"..v)
            return P.insert(_bl, a, v)
        end
    }
    setmetatable(bl, mt)
    return bl
end

function P:match(v)

    -- first: plain hash check
    local l = self[v]
    if l then 
        return l 
    end
    
    -- too big request? -> return nil
    if v > self.max then
        return nil
    end 
    
    -- second: sorted
    local a = self.indx
    for _,i in ipairs(a) do
        if v <= i then
            return self[l] + (v - l)
        end
        l = i
    end

    if l then
        return self[l] + (v - l)
    end
    return nil
end

function P:insert(i, v)

    local a = self.indx
    local nr_entries = #a
    local maxi = self.max
    self.max = maxi > i and maxi or i
    local last_entry = a[nr_entries]
    if last_entry and v - i + last_entry - self[last_entry] == 0 then
        return
    end

    if not self[i] then
        if nr_entries > 0 then
            if i > a[nr_entries] then
                self[i] = v
                push(a, i)
            else
                local old_i = P.match(self, i+1)
                self[i] = v
                push(a, i)
                if not self[i+1] then
                    self[i+1] = old_i
                    push(a, i+1)
                end
            end
        else
            self[i] = v
            push(a, i)
        end
    else
        local nexti = i+1
        if not (nexti > a[nr_entries]) and not self[nexti] then
            local old_i = self[i]
            self[i] = v
            self[nexti] = old_i+1
            push(a, nexti)
        else
            self[i] = v
        end
    end

    sort(a)
    local diff
    local newa = {}
    for i,n in ipairs(a) do
        if not diff then
            diff = self[n] - n
            push(newa, n)
        else 
            local newdiff = self[n] - n
            if diff ~= newdiff then
                diff = newdiff
                push(newa, n)
            else
                self[n] = nil
            end
        end
    end
    self.indx = newa
--    for i,e in ipairs(newa) do
--        print("i:"..i..",e:"..e..",v:"..(self[e] or '<>')..",c:"..self.max)
--    end
--    for i,e in pairs(newa) do
--        print("oi:"..i..",e:"..e..",v:"..(self[e] or '<>')..",c:"..self.max)
--    end
--    for i,e in pairs(self) do
--        print("w:"..i)
--    end
--    for i,e in ipairs(self) do
--        print("sw:"..i)
--    end
    return
end


if _REQUIREDNAME == nil then
    list = P
else
    _G[_REQUIREDNAME] = P
end


return list
