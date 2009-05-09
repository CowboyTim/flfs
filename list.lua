
local P = {}

local sort = table.sort
local push = table.insert

function P:new(bl)

    -- new list
    bl = bl or {}
    setmetatable(bl, self)
    self.__index = self

    -- add the index
    local a = bl.indx or {}
    for n in pairs(bl) do
        push(a, n) 
    end
    sort(a)
    bl.indx = a
    bl.max  = 0
    return bl
end

function P:match(v)

    -- first: plain hash check
    local l = self[v]
    if l then 
        return l 
    end
    
    local a = self.indx
    l = a[#a]
    if v > l then
        return self[l] + (v - l)
    end 
    
    -- second: sorted
    for _,i in ipairs(a) do
        if v <= i then
            return self[l] + (v - l)
        end
        l = i
    end
    return self[l] + (v - l)
end

function P:insert(i, v)
    --print("INSERT:i"..i..",v:"..v)
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
                local old_i = self:match(i+1)
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
--        print("checking:"..i..",n:"..n..",diff:"..(diff or '<>'))
        
        if not diff then
            diff = self[n] - n
            push(newa, n)
        else 
            local newdiff = self[n] - n
--            print("newdiff:"..newdiff)
            if diff ~= newdiff then
                diff = newdiff
                push(newa, n)
            else
--                print("removing:"..i)
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
