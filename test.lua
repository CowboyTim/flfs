
require 'os'

m = 2 * 1024 * 1024 * 1024 * 1024
b = 1024 * 1024
print('max:'..m..',b:'..b..',count:'..m/b)
--t = {}
--for i=1,m/b do
--    t[i] = 
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'..
--        '1111111111111111'
--end

print('done:'..(string.format('%d',2^52 + 10)))

y = {}
for i=5,25 do
    table.insert(y, i)
end

print("t:"..table.concat(y, ','))
local a = table.remove(y)
print("a:"..a..",t:"..table.concat(y, ','))

local push   = table.insert
local sort   = table.sort
local delete = table.remove

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

require 'list'

local n = { 
    list={[56666]=56667, [666]=666, [8888]=9999 },
    map={[0]=56666,[6]=666,[10]=8888}
}
n = list:new(n)
print(list.tostring(n))
for i, v in ipairs(n.indx) do
    print("i:"..i..",v:"..v)
end



local tbl = {
    list={[55]=121, [131]=131,  [33]=33, [667]=667,  [800]=800, [710]=711},   
    map ={[0]=55, [76]=131, [77]=33, [78]=667, [100]=800, [121]=710}
}


tbl = list:new(tbl)
print(tbl[21])
print(tbl[0])
print(tbl[1])
print(tbl[1])
print(tbl[11])
print(tbl[61])
print(tbl[78])
print(tbl[77])
print(tbl[0])
print(tbl[99])
print(tbl[100])
print(tbl[101])
print(tbl[122])
print('toobig:'..tostring(tbl[123]))
tbl[0] = 909
print(list.tostring(tbl))
print(tbl[0])
print(tbl[1])
print(tbl[2])
tbl[78] = 555666
print(list.tostring(tbl))
print(tbl[78])
print(tbl[79])
print(tbl[60])
tbl[60] = 999999
print(list.tostring(tbl))
print(tbl[59])
print(tbl[60])
print(tbl[61])
print(tbl[80])
print(tbl[29])
print(tbl[31])
tbl[1] = 111111111
print(list.tostring(tbl))
print(tbl[0])
print(tbl[1])
print(tbl[2])
print(tbl[3])
tbl[30] = 7778888
print(list.tostring(tbl))
print(tbl[29])
print(tbl[30])
print(tbl[31])
print(tbl[32])
print(tbl[60])
tbl[2] = 888888888
print(list.tostring(tbl))
print(tbl[0])
print(tbl[1])
print(tbl[2])
print(tbl[3])
print(tbl[4])
print('TT:'..tbl[24])
tbl[25] = 252525252525
print(tbl[24])
print(tbl[25])
print(tbl[26])
print(tbl[101])
print(tbl[121])
print(tbl[122])
print('toobig:'..tostring(tbl[123]))
tbl[123] = 53
tbl[150] = 999
tbl[149] = 888
tbl[148] = 333
tbl[148] = 444
print(tbl[123])
print(tbl[148])
print(tbl[149])
print(tbl[150])
print('toobig:'..tostring(tbl[151]))
tbl[130] = 2007
print(tbl[130])
print(tbl[131])
print('tostring:'..tostring(tbl[151]))
tbl[200] = 4000
print(tbl[199])
print(tbl[200])
print("TEST:APPEND")
tbl[201] = 556562562
print(tbl[201])
print('toobig:'..tostring(tbl[202]))

oldprint = print
--print = function () end
--
local tbl1 = list:new()
local tbl2 = list:new()

tbl1[0] = 6667
tbl1[1] = 6668
tbl1[2] = 6669
print(list.tostring(tbl1))

tbl2[0] = 5556
tbl2[1] = 6000
tbl2[2] = 6001
tbl2[3] = 500
tbl2[5] = 1000
tbl2[8] = 6670
tbl2[9] = 6671
print(list.tostring(tbl2))

local t = list.mergetofreelist(tbl1, tbl2)
print('result:'..list.tostring(t))

print('last:'..list.getlast(t))
print('result:'..list.tostring(t))
print('last:'..list.getlast(t))
print('result:'..list.tostring(t))

local function myconcat(t,aa)
    local tt = {}
    for a,b in pairsByKeys(t) do
        table.insert(tt, '['..a..']='..b)
    end
    return table.concat(tt,aa)
end

local pt = {}
local p = list:new()
    print("TEST:"..3)
    for i=0,63 do
        v = 3*64 + i
        print('i:'..i..',p:'..v)
        p[i] = v
        print(list.tostring(p))
        pt[i] = v
        print(myconcat(pt, ','))
    end
    print("TEST:"..2)
    for i=64,127 do
        v = 2*64  + i - 64
        print('i:'..i..',p:'..v)
        p[i] = v
        print(list.tostring(p))
        pt[i] = v
        print(myconcat(pt, ','))
    end
    print("TEST:"..1)
    for i=128,191 do
        v = 1*64  + i - 64 * 2
        print('i:'..i..',p:'..v)
        p[i] = v
        print(list.tostring(p))
        pt[i] = v
        print(myconcat(pt, ','))
    end
    print("TEST:"..0)
    for i=192,255 do
        v = 0*64  + i - 64 * 3
        print('i:'..i..',p:'..v)
        p[i] = v
        print(list.tostring(p))
        pt[i] = v
        print(myconcat(pt, ','))
    end

print(getmetatable(t))
print(list.tostring(t))

print("PERFORMANCE TEST")

for i=0,100 do
    local tbl = {
        list={[55]=121, [131]=131,  [33]=33, [667]=667,  [800]=800, [710]=711},   
        map ={[0]=55, [76]=131, [77]=33, [78]=667, [100]=800, [121]=710}
    }
    tbl = list:new(tbl)
    for i=0, 130 do
        local l = tbl[i]
    end
end

for i,e in ipairs(tbl.indx) do
    print("i:"..i..",e:"..e)
end
print('start')

n = list:new()

for i=0,100 do
    n[i] = 6666666666+i
end
for i=100,200 do
    n[i] =77777+i-100
end
for i=200,3000 do
    n[i] = 99999+i-200
end

print(list.tostring(n))
print("start:rewrite")

for k=1,3 do
oldprint("doing k:"..k)
for i=0,3000 do
    n[i] = k*3000 +i+k
end
end

print = oldprint

oldprint(list.tostring(n))
list.truncate(n, 0)
oldprint(list.tostring(n))

oldprint(list.tostring(p))
list.truncate(p, 70)
oldprint(list.tostring(p))
list.truncate(p, 64)
oldprint(list.tostring(p))
list.truncate(p, 1)
oldprint(list.tostring(p))

list.truncate(p, 0)
oldprint(list.tostring(p))
