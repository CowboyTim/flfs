
local P = {}

local sort = table.sort
local push = table.insert
local join = table.concat

function P:tostring()
    local l = {}
    local t = {}
    local bl = rawget(self, '_list')
    for i, v in ipairs(bl.indx) do
        --print("ts:"..tostring(i)..","..tostring(v))
        push(t, '['..v..']='..bl[v])
        push(l, '['..v..']='..bl.list[v])
    end
    local k = {}
    push(k, 'list={'..join(l, ',')..'}')
    push(k, 'map={'..join(t, ',')..'}')
    return join(k, ',')
end

function P:new(data)
    --print("LIST:new()")

    -- new list
    local bl = {}

    -- add the index index
    local index = {}
    local list  = data and data.list or {}
    local map   = data and data.map  or {}
    for n, v in pairs(list) do
        bl[n] = map[n]
        push(index, n) 
    end
    sort(index)
    bl.indx  = index
    bl.list  = list

    -- set the correct metatable 'tie'
    local _bl = bl
    bl = {_list = _bl}
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
    
    -- too big request? -> return nil
    if v > list[index[#index]] then
        return nil
    end 
    
    -- second: sorted
    for j=1,#index do
        local a = index[j]
        --print("testing:i:"..j..":v:"..v..","..tostring(a)..",list:"..tostring(list[a]))
        -- FIXME: implement faster stop in case of non match
        if a and v >= a and v <= list[a] then
            return self[a] + (v - a)
        end
    end

    return nil
end

function P:truncate(i)
end

function P:merge(b)
    local a       = rawget(self, '_list')
    local self_b  = rawget(b,'_list')
    --print("merge:"..tostring(a)..",b:"..tostring(b))
    local list_b  = self_b.list
    local index_b = self_b.indx
    local m = 0
    if #(a.indx) ~= 0 then
        m = a.indx[#(a.indx)] + 1
    end
    --print("m:"..m)
    for i,v in ipairs(index_b) do
        --print("bi:"..i..",bv:"..v)
        a.list[m] = (list_b[v] - (i-1)) + m
        a[m]      = self_b[v]
        push(a.indx, m)
        m = m +1
    end
    
    --print("before cc:"..P.tostring({_list=self}))

    P._canonicalize(a)
    return self
end

function P:insert(i, v)

    --print("insert:"..P.tostring({_list=self}))

    local index = self.indx
    local list  = self.list

    if #index == 0 then
        -- empty list: add the entry
        self[i] = v
        list[i] = i
        push(index, i)
        return
    end

    local last_index = index[#index]
    --print("last_index:"..last_index)

    if i == list[last_index] + 1 and self[last_index] + list[last_index] + 1 - last_index == v then
        -- plain append
        --print("plain append")
        list[last_index] = list[last_index] + 1
        return
    elseif i > list[last_index] then
        -- sparse append: just add
        --print("sparse append")
        self[i] = v
        list[i] = i
        push(index, i)
        return
    elseif list[i] and list[i] - i == 0 then
        -- item exists and is size 1; just update
        --print("hash append")
        self[i] = v
    elseif list[i] then
        -- at the start. NOTE: i+1 will not exist, as size > 1
        --print("start append")
        local n = i+1
        list[n] = list[i]
        self[n] = self[i] + 1
        push(index, n)
        list[i]   = i
        self[i]   = v


    else
    
        -- item didn't exist directly: search for the base
        for j=1,#index do
            -- FIXME: implement faster stop in case of non match
            local a = index[j]
            --print("a:"..a..",i:"..i..",list[a]:"..list[a]..",self:"..self[a])
            if i >= a and i <= list[a] then
                if list[a] - i == 0 then
                    -- entirely at the end: just add and shrink
                    list[i] = i
                    self[i] = v
                    list[a] = list[a] - 1
                    push(index, i)
                else
                    -- in the middle
                    local old = list[a]
                    list[a] = i - 1
                    list[i] = i
                    self[i] = v
                    push(index, i)
                    list[i+1] = old
                    self[i+1] = self[a] + (i - a) + 1
                    push(index, i+1)
                end
                break
            end
        end
    end

    P._canonicalize(self)

    return
end

function P:_canonicalize()
    local index = self.indx
    local list  = self.list

    local newindex = {}
    sort(index)
    push(newindex, index[1])
    local l = 1
    for i=2,#index do
        --print("iaaaaaaaaaaaaaaaaaaaaaaa:"..i)
        local previous_index = index[l]
        local p = list[previous_index] + 1
        if index[i] and index[i] == previous_index + p
                    and self[index[i]] == self[previous_index] + p then
            self[index[i]] = nil
            list[index[l]] = list[index[i]]
            list[index[i]] = nil
        else 
            push(newindex, index[i])
            l = i
        end
    end

--    for i,e in pairs(self) do
--        --print("m:"..i..",o:"..tostring(e))
--    end
--    for i,e in pairs(self.list) do
--        --print("w:"..i..",o:"..e)
--    end
--    for i,e in ipairs(self.indx) do
--        --print("sw:"..i..",e:"..e)
--    end
    self.indx = newindex
--    for i,e in ipairs(self.indx) do
--        --print("i:"..i..",mapsto:"..e..",end:"..self.list[e]..",block:"..self[e])
--    end
end


if _REQUIREDNAME == nil then
    list = P
else
    _G[_REQUIREDNAME] = P
end


return list
