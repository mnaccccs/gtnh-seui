-- lib.drone exact Wiki fleet distribution regression test
package.path = "./?.lua;./?/init.lua;" .. package.path
local logs={}
package.preload["lib.log"] = function() return {warn=function(_,m)logs[#logs+1]=m end,info=function(_,m)logs[#logs+1]=m end} end
local drone=require("lib.drone")
local calls,readCounts={},{}
-- Shared box contains MK-X in zero-based slot 0 and MK-VI in slot 1.
-- Only transposer 1 has a reliable current inventory view; the other remote views are deliberately stale/empty.
local shared={
 [0]={name="gtnhintergalactic:item.MiningDrone",damage=9,size=64},
 [1]={name="gtnhintergalactic:item.MiningDrone",damage=5,size=64},
}
local function tp(id)
 return{
  getAllStacks=function(side)
   readCounts[id]=(readCounts[id]or 0)+1
   return{getAll=function() if id==1 then return shared else return{} end end}
  end,
  transferItem=function(fromSide,toSide,count,slot)
   calls[#calls+1]={id=id,fromSide=fromSide,toSide=toSide,count=count,slot=slot}
   if fromSide==1 then return 0 end
   assert(slot==1,"all miners must use MK-X slot 1, got "..tostring(slot))
   assert(count==1,"each miner gets exactly one drone")
   shared[0].size=shared[0].size-1
   return 1
  end,
 }
end
local hw={miners={{},{},{}},transposers={
 {address="tp1",proxy=tp(1)},{address="tp2",proxy=tp(2)},{address="tp3",proxy=tp(3)},
}}
local assignment={domain="miner",worker={address="m1"},target={route={}},params={droneTier=10,distance=100}}
local cfg={droneBackend="transposer",droneSide=0,inputSide=1,allowRandomDrone=false}
local ok,err=drone.prepare(assignment,cfg,hw)
assert(ok,err)
assert(readCounts[1]==1,"first shared inventory must be read exactly once")
assert(readCounts[2]==nil and readCounts[3]==nil,"must not reread stale remote ender-chest views")
assert(#calls==6,"three returns plus three one-item distributions")
for i=4,6 do assert(calls[i].slot==1 and calls[i].count==1,"uniform MK-X distribution")end
assert(shared[0].size==61 and shared[1].size==64,"MK-VI stack must remain untouched")
print("DRONE WIKI FLEET PASSED")
