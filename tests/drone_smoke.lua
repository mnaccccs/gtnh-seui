-- lib.drone Wiki-style fleet transfer smoke test
package.path = "./?.lua;./?/init.lua;" .. package.path
package.preload["lib.log"] = function() return {warn=function()end,info=function()end} end

local drone = require("lib.drone")
local sharedCount = 2
local calls = {}

local function makeTransposer(id)
  return {
    transferItem = function(fromSide, toSide, count, slot)
      calls[#calls + 1] = {id=id,fromSide=fromSide,toSide=toSide,count=count,slot=slot}
      if fromSide == 1 and toSide == 0 then return 0 end -- 输入总线原本为空
      if fromSide == 0 and toSide == 1 and sharedCount > 0 then
        sharedCount = sharedCount - 1
        return 1
      end
      return 0
    end,
    getAllStacks = function(side)
      assert(side == 0, "expected shared drone side")
      return {getAll=function()
        if sharedCount <= 0 then return {} end
        return {[0]={name="gtnhintergalactic:item.MiningDrone",damage=2,size=sharedCount}}
      end}
    end,
  }
end

local hw = {transposers={
  {address="tp-1",proxy=makeTransposer("tp-1")},
  {address="tp-2",proxy=makeTransposer("tp-2")},
}}
local assignment = {
  domain="miner",
  worker={address="any-miner"},
  target={route={}},
  params={droneTier=3},
}

local cfg = {droneBackend="transposer",droneSide=nil,inputSide=nil,allowRandomDrone=false}
local ok, err = drone.prepare(assignment,cfg,hw)
assert(not ok and tostring(err):find("droneSide/inputSide",1,true), "missing global sides must fail closed")

cfg.droneSide=0
cfg.inputSide=0
ok, err = drone.prepare(assignment,cfg,hw)
assert(not ok and tostring(err):find("不能相同",1,true), "equal sides must fail closed")

cfg.inputSide=1
ok, err = drone.prepare(assignment,cfg,hw)
assert(ok, err)
assert(sharedCount == 0, "all required drones must be distributed")
assert(#calls == 4, "expected two fleet returns and two fleet inserts")
assert(calls[1].fromSide == 1 and calls[1].toSide == 0, "old drones must return first")
assert(calls[2].fromSide == 1 and calls[2].toSide == 0, "all old drones must return before inserts")
assert(calls[3].fromSide == 0 and calls[3].toSide == 1, "new drone direction")
assert(calls[4].fromSide == 0 and calls[4].toSide == 1, "new drone direction")
print("drone fleet smoke: ALL PASSED")
