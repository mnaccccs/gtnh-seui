-- SEUI host-side logic tests (Lua 5.2/5.3)
package.path = "./?.lua;./?/init.lua;" .. package.path

local now = 100
package.preload["computer"] = function()
  return {uptime=function() return now end, freeMemory=function() return 1024*1024 end}
end
local function strictWtrunc(s, count)
  local width, finish = 0, 0
  while width < count do
    if finish >= #s then error("index " .. finish .. ", length " .. #s) end
    width, finish = width + 1, finish + 1
  end
  return finish > 1 and s:sub(1, finish - 1) or ""
end
package.preload["unicode"] = function()
  return {
    len=function(s) return #s end,
    wlen=function(s) return #s end,
    wtrunc=strictWtrunc,
  }
end
local logs = {}
package.preload["lib.log"] = function()
  local function add(level, domain, msg) logs[#logs+1]={level,domain,msg} end
  return {
    info=function(d,m)add("info",d,m)end,
    warn=function(d,m)add("warn",d,m)end,
    error=function(d,m)add("error",d,m)end,
    fatal=function(d,m)add("fatal",d,m)end,
    getRecent=function() return {} end,
  }
end
package.preload["lib.drone"] = function()
  return {prepare=function() return true end}
end

local function eq(actual, expected, msg)
  if actual ~= expected then error((msg or "assert") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual), 2) end
end
local function ok(value, msg) if not value then error(msg or "expected truthy",2) end end

-- format
local format = require("lib.format")
eq(format.fitCenter("PUMP", 6), " PUMP ", "short text must not call unsafe wtrunc")
eq(format.fit("ABCDEFG", 6), "ABCDEF", "long text truncates to exact width")
eq(format.fitRight("OK", 4), "  OK", "right padding")
eq(format.parseSize("10M"), 1e7, "parse 10M")
eq(format.parseSize("1.5G"), 1.5e9, "parse 1.5G")
local f = format.decodePackedBatch(107002, true, "v1_simple")
eq(f.planetType, 7, "v1 fluid planet")
eq(f.gasType, 2, "v1 fluid gas")
eq(f.stopAfter, true, "v1 stop flag")
local m = format.decodePackedBatch(80010011500, false, "v2.2_extended")
eq(m.droneTier, 800, "v2 drone decode preserves high encoding")
-- realistic v2: tier 8 + dist 100 + OC 1.15
m = format.decodePackedBatch(8e8 + 100e5 + 1.15e4, false, "v2.2_extended")
eq(m.droneTier, 8, "v2 drone")
eq(m.distance, 100, "v2 distance")
ok(math.abs(m.overdrive - 1.15) < 1e-9, "v2 overdrive")

-- model + scheduler
local model = require("lib.model")
local scheduler = require("lib.scheduler")
model.clear()
local t1 = model.addTarget{id="fluid:a",domain="pump",label="A",fluid="a",target=100,current=20,weight=0,order=1,route={planetType=2,gasType=1}}
local t2 = model.addTarget{id="fluid:b",domain="pump",label="B",fluid="b",target=100,current=50,weight=40,order=2,route={planetType=3,gasType=1}}
local workers = {{address="p1",threads=1,mult=4}}
local plan = scheduler.plan("pump", model.getByDomain("pump"), workers, now, {compatAllPumpsOneTarget=true,maxBatch=30})
eq(plan[1].target.id, "fluid:b", "weight affects scheduler")
-- hysteresis: running target at 95% must stay candidate until highRatio
model.clear()
t1 = model.addTarget{id="fluid:a",domain="pump",label="A",fluid="a",target=100,current=95,lowRatio=.9,highRatio=1,route={planetType=2,gasType=1}}
t1.runtime.state="RUN"
plan = scheduler.plan("pump", model.getByDomain("pump"), workers, now, {compatAllPumpsOneTarget=true,maxBatch=30})
eq(plan[1].target.id, "fluid:a", "hysteresis retains running target")
t1.current=100
plan = scheduler.plan("pump", model.getByDomain("pump"), workers, now, {compatAllPumpsOneTarget=true,maxBatch=30})
eq(plan, nil, "target at high ratio is done")

-- controller keyed backend writes every pump recipe and avoids duplicate reconfiguration
package.loaded["lib.controller"] = nil
local controller = require("lib.controller")
local params = {batch=1}
local active = false
local workAllowed = false
local setCount = 0
local proxy = {
  setWorkAllowed=function(v) workAllowed=v return true end,
  isMachineActive=function() return active end,
  setParameter=function(k,v) params[k]=v setCount=setCount+1 return true end,
  getParameters=function() return params end,
}
local pump = {address="pump-address",proxy=proxy,name="projectmodulepumpt2",threads=4,paramBackend="keyed"}
local hw = {pumps={pump},miners={},paramBackend="keyed",transposers={}}
local cfg = {idleTimeout=30,droneBackend="manual"}
controller.init(hw,cfg)
local target={id="fluid:test",domain="pump",route={}}
local assignment={worker=pump,domain="pump",target=target,params={planetType=7,gasType=2},batch=12,recipe=0}
ok(controller.enqueue(assignment),"enqueue")
for i=1,7 do now=now+1 controller.tick(now,cfg,hw) end
local status=controller.status()["pump-address"]
eq(status.phase,"RUNNING","controller reaches RUNNING")
eq(params["recipe0.planetType"],7,"recipe0")
eq(params["recipe3.gasType"],2,"recipe3")
eq(params.batch,12,"batch")
local before=setCount
ok(controller.enqueue(assignment),"duplicate enqueue")
now=now+1 controller.tick(now,cfg,hw)
eq(controller.status()["pump-address"].phase,"RUNNING","duplicate stays running")
eq(setCount,before,"duplicate does not rewrite")
controller.stopDomain("pump","done")
now=now+1 controller.tick(now,cfg,hw)
now=now+1 controller.tick(now,cfg,hw)
eq(controller.status()["pump-address"].phase,"IDLE","domain stop reaches IDLE")
eq(workAllowed,false,"domain stop disables machine")

print("ALL TESTS PASSED")
