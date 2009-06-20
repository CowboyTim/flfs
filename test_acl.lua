
require 'acl'

local l = acl.acl_from_text([[
user::rxw
group::r--
other::rwx
]])
print(tostring(l))
--local t = acl.acl_equiv_mode(l)

--print(acl.acl_to_text(l));

