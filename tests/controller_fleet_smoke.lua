-- controller fleet barrier smoke test: all miners stop before one global drone swap
package.path = "./?.lua;./?/init.lua;" .. package.path
local now = 0
package.preload["computer"] = function() return {uptime=function() return now end} end
package.preload["lib.log"] = function()
  return {info=function()end,warn=function()end,error=function()end}
end

local prepareCalls = 0
local states = {}
package.preload["lib.drone"] = function()
  return {
    backend=function() return "transposer" end,
    prepare=function()
      prepareCalls = prepareCalls + 1
      for _, s in pairs(states) do
        assert(s.workAllowed == false, "fleet prepare ran before every miner was disabled")
        assert(s.active == false, "fleet prepare ran before every miner was idle")
      end
      return true
    end,
  }
end

local function makeMiner(address, active)
  local s = {active=active,workAllowed=true,params={distance=0}}
  states[address] = s
  local proxy = {
    setWorkAllowed=function(v) s.workAllowed=v return true end,
    isMachineActive=function() return s.active end,
    setParameter=function(k,v) s.params[k]=v return true end,
    getParameters=function() return s.params end,
  }
  return {address=address,proxy=proxy,name="projectmoduleminert3",paramBackend="keyed"}
end

local m1 = makeMiner("miner-1", false)
local m2 = makeMiner("miner-2", true)
local hw = {pumps={},miners={m1,m2},transposers={{address="tp",proxy={}}},paramBackend="keyed"}
local cfg = {idleTimeout=30,droneBackend="transposer"}
local controller = require("lib.controller")
controller.init(hw,cfg)
local target={id="item:test",domain="miner",route={droneTier=3,distance=100}}
assert(controller.enqueue{worker=m1,domain="miner",target=target,params={droneTier=3,distance=100}})
assert(controller.enqueue{worker=m2,domain="miner",target=target,params={droneTier=3,distance=100}})

now=1; controller.tick(now,cfg,hw) -- both REQUEST_STOP -> WAIT_IDLE
now=2; controller.tick(now,cfg,hw) -- m1 PREPARE, m2 still active
assert(prepareCalls == 0, "must not swap while one miner is active")
states["miner-2"].active=false
now=3; controller.tick(now,cfg,hw) -- m2 reaches PREPARE; barrier waits until next tick
assert(prepareCalls == 0, "barrier should run only after both PREPARE states are visible")
now=4; controller.tick(now,cfg,hw) -- one fleet prepare, then APPLY
assert(prepareCalls == 1, "fleet drone preparation must run exactly once")
now=5; controller.tick(now,cfg,hw) -- VERIFY
now=6; controller.tick(now,cfg,hw) -- START
assert(controller.status()["miner-1"].phase == "RUNNING")
assert(controller.status()["miner-2"].phase == "RUNNING")
assert(states["miner-1"].params.distance == 100 and states["miner-2"].params.distance == 100,
  "successful fleet drone distribution must continue to APPLY distance on every miner")
assert(states["miner-1"].workAllowed and states["miner-2"].workAllowed,
  "miners must restart after distance verification")
assert(prepareCalls == 1, "per-worker duplicate fleet swaps are forbidden")
print("controller fleet barrier smoke: ALL PASSED")
