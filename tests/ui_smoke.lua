-- UI smoke test with mocked OpenComputers GPU/screen
package.path = "./?.lua;./?/init.lua;" .. package.path
local now=1
package.preload["sides"]=function()return{down=0,up=1,north=2,south=3,west=4,east=5}end
package.preload["computer"]=function() return {uptime=function()return now end,freeMemory=function()return 1024*1024 end} end
local function strictWtrunc(s,n)local w,e=0,0;while w<n do if e>=#s then error("index "..e..", length "..#s)end;w=w+1;e=e+1 end;return e>1 and s:sub(1,e-1)or""end
package.preload["unicode"]=function() return {wlen=function(s)return #s end,wtrunc=strictWtrunc,char=function(n)return string.char(n)end} end
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
function gpu.set()return true end
local screen={address="screen"}
function screen.setTouchModeInverted()return false end
function screen.setPrecise()return false end
package.preload["component"]=function()return {gpu=gpu,screen=screen}end
package.preload["term"]=function()return {clear=function()end}end
package.preload["lib.log"]=function()return {info=function()end,warn=function()end,error=function()end,getRecent=function()return{}end}end
package.preload["lib.inventory"]=function()return {getSnapshot=function()return{duration=0,timestamp=now}end}end
package.preload["lib.controller"]=function()return {status=function()return{}end,stopAll=function()end,retry=function()return true end}end

local model=require("lib.model")
model.clear()
local t=model.addTarget{id="fluid:test",domain="pump",label="Test",fluid="test",target=100,current=20,route={planetType=2,gasType=1}}
t.runtime.state="LOW"
local ui=require("lib.ui")
local cfg=require("config")
ui.init(gpu,screen,cfg)
local hw={pumps={},miners={},levelMaintainers={},transposers={},paramBackend="keyed"}
local app={config=cfg,configDirty=false,nextInventoryScan=1,needRescan=false}
ui.render(hw,cfg,now,model.getTargets(),true)
-- 目标第一行仍可点击
ui.dispatch({"touch","screen",2,5,0,"Player"},app)
assert(ui.getState().selectedId=="fluid:test","target hitbox")
-- 选中目标后直接键入数字，无需先点编辑按钮。
ui.dispatch({"key_down","keyboard",49,2,"Player"},app)
ui.dispatch({"key_down","keyboard",48,11,"Player"},app)
ui.dispatch({"key_down","keyboard",13,28,"Player"},app)
assert(t.target==10,"direct keyboard target input")
ui.render(hw,cfg,now,model.getTargets(),true)
-- 无 dirty 的下一帧后 hitbox 仍应存在
ui.render(hw,cfg,now,model.getTargets(),true)
ui.dispatch({"touch","screen",144,1,0,"Player"},app)
assert(ui.getState().page=="miner","persistent header hitbox")
print("UI SMOKE PASSED")
