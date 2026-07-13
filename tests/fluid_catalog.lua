-- 40-fluid catalog and requester merge regression test
package.path="./?.lua;./?/init.lua;"..package.path
package.preload["unicode"]=function()return{wlen=function(s)return#s end,wtrunc=function(s,n)return s:sub(1,n-1)end}end
package.preload["lib.log"]=function()return{info=function()end}end
local model=require("lib.model")
local catalog=require("lib.fluid_catalog")
model.clear()
assert(#catalog.entries==40,"catalog must contain exactly 40 routes")
assert(catalog.populate(model)==40,"initial catalog population")
assert(#model.getByDomain("pump")==40,"pump page must show all 40 fluids")
for _,t in ipairs(model.getByDomain("pump"))do assert(t.mode=="OFF" and t.target==0,"catalog defaults must be safe OFF")end
local maint={address="maint",proxy={getSlot=function(slot)
 if slot==1 then return{isEnable=true,isFluid=true,name="hydrogen",label="氢气液滴",quantity=1e12,batch=8001,fluid={name="hydrogen"}}end
 return{isEnable=false}
end}}
assert(model.importFromMaintainers({maint},"v1_simple")==1)
assert(#model.getByDomain("pump")==40,"requester import must merge by route, not duplicate")
local h
for _,t in ipairs(model.getByDomain("pump"))do if t.route.planetType==8 and t.route.gasType==1 then h=t end end
assert(h and h.mode=="TARGET" and h.target==1e12,"imported route must become active target")
assert(h.route.baseRate==1568000,"catalog extraction rate must survive import")
model.updateCurrent(h,{fluids={hydrogen=12345},timestamp=1,items={}})
assert(h.current==12345,"catalog aliases must read AE inventory")
print("FLUID CATALOG PASSED")
