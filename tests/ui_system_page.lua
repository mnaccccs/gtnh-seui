-- SYSTEM 页多机器渲染回归：
-- 1) 机器状态列表不再截断为 5 台，右栏装得下的机器全部绘制；
-- 2) 屏幕高度装不下时显示“还有 N 台未显示”，而不是静默丢弃；
-- 3) OC 组件计数诊断行可用且不依赖 computer.componentCount 存在。
package.path = "./?.lua;./?/init.lua;" .. package.path
local now=1
package.preload["sides"]=function()return{down=0,up=1,north=2,south=3,west=4,east=5}end
package.preload["computer"]=function()
  return {uptime=function()return now end,freeMemory=function()return 1024*1024 end,componentCount=function()return 16 end}
end
local function strictWtrunc(s,n)local w,e=0,0;while w<n do if e>=#s then error("index "..e..", length "..#s)end;w,e=w+1,e+1 end;return e>1 and s:sub(1,e-1)or""end
package.preload["unicode"]=function() return {wlen=function(s)return #s end,wtrunc=strictWtrunc,char=function(n)return string.char(n)end} end
local drawn={}
local gpu={address="gpu",fg=0xffffff,bg=0,res={80,25}}
function gpu.getForeground()return gpu.fg,false end
function gpu.getBackground()return gpu.bg,false end
function gpu.setForeground(v)gpu.fg=v return v end
function gpu.setBackground(v)gpu.bg=v return v end
function gpu.getResolution()return gpu.res[1],gpu.res[2] end
function gpu.setResolution(w,h)gpu.res={w,h} return true end
function gpu.setDepth()return 8 end
function gpu.bind()return true end
function gpu.fill()return true end
function gpu.set(x,y,s)drawn[#drawn+1]={x=x,y=y,text=tostring(s)} return true end
local screen={address="screen"}
function screen.setTouchModeInverted()return false end
function screen.setPrecise()return false end
package.preload["component"]=function()return {gpu=gpu,screen=screen}end
package.preload["term"]=function()return {clear=function()end}end
package.preload["lib.log"]=function()return {info=function()end,warn=function()end,error=function()end,getRecent=function()return{}end}end
package.preload["lib.inventory"]=function()return {getSnapshot=function()return{duration=0,timestamp=now}end}end

-- lib.ui 加载时就会 require lib.controller，因此 mock 必须在 require ui 之前注册。
local statusSnapshot = {}
package.preload["lib.controller"]=function()
  return {status=function()return statusSnapshot end,stopAll=function()end,retry=function()return true end}
end

local function makeStatus(count, phase, withError)
  local ws={}
  for i=1,count do
    ws[string.format("aa%06d-machine",i)] = {
      phase=phase, domain="miner",
      servingTarget=withError and nil or "item:test",
      hasPending=false,
      lastError=withError and ("fault "..i) or nil,
    }
  end
  return ws
end

local ui=require("lib.ui")
local cfg=require("config")
ui.init(gpu,screen,cfg)
ui.setState({page="system"})
local hw={pumps={},miners={},levelMaintainers={},transposers={},paramBackend="keyed"}

local function findDrawn(needle)
  for _,d in ipairs(drawn) do
    if d.text and d.text:find(needle,1,true) then return true end
  end
  return false
end

-- 场景一：12 台正常机器（各占 1 行），全部应绘制且组件计数行出现。
drawn={}
statusSnapshot=makeStatus(12,"RUNNING",false)
ui.markDirty()
ui.render(hw,cfg,now,{},true)
for i=1,12 do
  assert(findDrawn(string.format("aa%06d",i)), "machine "..i.." missing from system page")
end
assert(findDrawn("components: 16"), "component count line missing")
assert(not findDrawn("还有"), "overflow hint should not appear when list fits")

-- 场景二：12 台 FAULT 机器（各占 2 行，共 24 行 > 屏幕可用行），应给出未显示提示且不崩溃。
drawn={}
statusSnapshot=makeStatus(12,"FAULT",true)
ui.markDirty()
ui.render(hw,cfg,now,{},true)
assert(findDrawn("还有"), "overflow hint missing for oversized machine list")
assert(findDrawn("fault 1"), "first fault error should still be rendered")

print("UI SYSTEM PAGE PASSED")
