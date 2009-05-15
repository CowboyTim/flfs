
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
    local map   = data.map or {}
    for n, v in pairs(map) do
        bl[n] = map[n]
        push(index, n) 
    end
    sort(index)
    bl.indx = index
    bl.list = data.list or {}

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
    if v > index[#index] + (list[self[index[#index]]] - self[index[#index]]) then
        return nil
    end 
    
    -- second: sorted
    for j=1,#index do
        local a = index[j]
        --print("testing:i:"..j..":v:"..v..","..tostring(a)..",list:"..tostring(list[a]))
        -- FIXME: implement faster stop in case of non match
        if v >= a and v <= a + (list[self[a]] - self[a]) then
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
        a.list[self[m]] = (list_b[self[v]] - (i-1)) + m
        a[m]            = self_b[v]
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
        list[v] = i
        push(index, i)
        return
    end

    local last_index = index[#index]
    --print("last_index:"..last_index)
    local last_block = self[last_index]
    local list_i     = list[self[i]]

    if i == list[last_block] + 1 and  last_block + list[last_block] + 1 - last_index == v then
        -- plain append
        --print("plain append")
        list[last_block] = list[last_block] + 1
        return
    elseif i > list[last_block] then
        -- sparse append: just add
        --print("sparse append")
        self[i] = v
        list[v] = i
        push(index, i)
        return
    elseif list_i and list_i - i == 0 then
        -- item exists and is size 1; just update
        --print("hash append")
        self[i] = v
    elseif list_i then
        -- at the start. NOTE: i+1 will not exist, as size > 1
        --print("start append")
        local n = i+1
        self[n]         = self[i] + 1
        list[self[n]]   = list_i
        push(index, n)
        self[i]         = v
        list[self[i]]   = i


    else
    
        -- item didn't exist directly: search for the base
        for j=1,#index do
            -- FIXME: implement faster stop in case of non match
            local a = index[j]
            list_i  = list[self[a]]
            --print("a:"..a..",i:"..i..",list[a]:"..list[a]..",self:"..self[a])
            if i >= a and i <= list_i then
                if list_i - i == 0 then
                    -- entirely at the end: just add and shrink
                    self[i] = v
                    list[self[i]] = i
                    list[self[a]] = list_i - 1
                    push(index, i)
                else
                    -- in the middle
                    local old = list_i
                    list[self[a]] = i - 1
                    self[i] = v
                    list[self[i]] = i
                    push(index, i)
                    self[i+1] = self[a] + (i - a) + 1
                    list[self[i+1]] = old
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
        local p = list[self[previous_index]] + 1
        if index[i] and index[i] == previous_index + p
                    and self[index[i]] == self[previous_index] + p then
            self[index[i]] = nil
            list[self[index[l]]] = list[self[index[i]]]
            list[self[index[i]]] = nil
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
