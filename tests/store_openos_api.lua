-- store.lua OpenOS `unserialize` API regression test
package.path="./?.lua;./?/init.lua;"..package.path
local base="./tests/.tmp-store.dat"
local function exists(p)local f=io.open(p,"r");if f then f:close()return true end return false end
package.preload["filesystem"]=function()return{
 path=function()return"./tests/"end,exists=exists,makeDirectory=function()return true end,
 remove=function(p)return os.remove(p)end,rename=function(a,b)return os.rename(a,b)end,
}end
local unserializeCalls=0
package.preload["serialization"]=function()return{
 serialize=function(v)return string.format("{schemaVersion=%d,name=%q}",v.schemaVersion,v.name)end,
 unserialize=function(s)
   unserializeCalls=unserializeCalls+1
   local fn,err=load("return "..s)
   if not fn then return nil,err end
   local ok,v=pcall(fn);if not ok then return nil,v end;return v
 end,
}end
package.preload["lib.log"]=function()return{info=function()end,warn=function()end}end
for _,p in ipairs{base,base..".bak",base..".tmp"}do os.remove(p)end
local store=require("lib.store")
store.init(base)
local ok,err=store.saveAtomic{schemaVersion=1,name="测试"}
assert(ok,err)
assert(unserializeCalls>=1,"OpenOS unserialize was not used for roundtrip verification")
local data,loadErr=store.load()
assert(data,loadErr)
assert(data.schemaVersion==1 and data.name=="测试","saved data did not roundtrip")
for _,p in ipairs{base,base..".bak",base..".tmp"}do os.remove(p)end
print("STORE OPENOS API PASSED")
