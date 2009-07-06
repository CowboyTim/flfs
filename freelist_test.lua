
require 'lunit'
local freelist = require 'freelist'

module( "freelist_test", lunit.testcase, package.seeall )

function test_ww ()
    local a = freelist:new()
    print(a:tostring())

    a:add({[4]=5})
    print(a:tostring())
    a:add({[6]=6})
    print(a:tostring())
    a:add({[10]=500})
    print(a:tostring())

    a:add({[502]=502})
    print(a:tostring())

    a:add({[9]=9})
    a:add({[600]=600})
    a:add({[605]=605})
    print(a:tostring())

    local s = a:getnextstride(1)
    assert_equal(605, s)
    print(a:tostring())

    local s = a:getnextstride(3)
    assert_equal(4, s)
    print(a:tostring())

    local s = a:getnextstride(1)
    assert_equal(600, s)
    print(a:tostring())

    local s = a:getnextstride(1)
    assert_equal(502, s)
    print(a:tostring())

    local s = a:getnextstride(492)
    assert_equal(9, s)
    print(a:tostring())

    local s = a:getnextstride(492)
    assert_equal(nil, s)
    print(a:tostring())

    a:add({[66]=70})
    a:add({[90]=90})
    print(a:tostring())

    local s = a:getnextstride(2)
    assert_equal(66, s)
    print(a:tostring())

    local s = a:getnextstride(2)
    assert_equal(67, s)
    print(a:tostring())

    local s = a:getnextstride(1)
    assert_equal(90, s)
    print(a:tostring())

    local s = a:getnextstride(1)
    assert_equal(68, s)
    print(a:tostring())

    local s = a:getnextstride(1)
    assert_equal(69, s)
    print(a:tostring())

    local s = a:getnextstride(1)
    assert_equal(70, s)
    print(a:tostring())

    local s = a:getnextstride(1)
    assert_equal(nil, s)
    print(a:tostring())

    local n = freelist:new()
    n:add({[55555]=66666666})
    print(n:tostring())

end
