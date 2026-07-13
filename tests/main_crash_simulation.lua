-- Main crash-path smoke test: restored terminal, persistent report, acknowledgement wait
package.path="./?.lua;./?/init.lua;"..package.path
if not table.pack then function table.pack(...) return {n=select('#',...),...} end end
local now,pulls,clears=0,0,0
package.preload["sides"]=function()return{down=0,up=1,north=2,south=3,west=4,east=5}end
package.preload["computer"]=function()return{uptime=function()now=now+.1 return now end,freeMemory=function()return 1024*1024 end}end
local function strictWtrunc(s,n)local w,e=0,0;while w<n do if e>=#s then error("index "..e..", length "..#s)end;w=w+1;e=e+1 end;return e>1 and s:sub(1,e-1)or""end
package.preload["unicode"]=function()return{wlen=function(s)return #s end,wtrunc=strictWtrunc}end
local gpu={address="gpu",fg=0xffffff,bg=0,res={80,25}}
function gpu.getForeground()return gpu.fg,false end; function gpu.getBackground()return gpu.bg,false end
function gpu.setForeground(v)gpu.fg=v return v end; function gpu.setBackground(v)gpu.bg=v return v end
function gpu.getResolution()return gpu.res[1],gpu.res[2]end; function gpu.setResolution(w,h)gpu.res={w,h}return true end
function gpu.setDepth()return 8 end; function gpu.bind()return true end; function gpu.fill()return true end
function gpu.set()error("forced GPU crash")end
local screen={address="screen",setTouchModeInverted=function()return false end,setPrecise=function()return false end}
local function emptyIter() return function() return nil end end
package.preload["component"]=function()return{gpu=gpu,screen=screen,list=function()return emptyIter()end,proxy=function()end,methods=function()return{}end}end
package.preload["event"]=function()return{pull=function(timeout)pulls=pulls+1;return "key_down" end}end
package.preload["term"]=function()return{clear=function()clears=clears+1 end}end
package.preload["shell"]=function()return{parse=function()return {},{simulate=true}end}end
package.preload["filesystem"]=function()return{
 path=function()return "."end,exists=function(p)local f=io.open(p,"r");if f then f:close()return true end return false end,
 makeDirectory=function()return true end,remove=function(p)return os.remove(p)end,rename=function(a,b)return os.rename(a,b)end,
}end
package.preload["serialization"]=function()return{serialize=function()return"{}"end,deserialize=function()return{}end}end
local cfg=dofile("config.lua")
cfg.dataFile="./tests/.tmp-crash.dat";cfg.logFile="./tests/.tmp-crash.log";cfg.crashFile="./tests/.tmp-crash-report.log"
package.preload["config"]=function()return cfg end
for _,p in ipairs{cfg.dataFile,cfg.dataFile..".bak",cfg.logFile,cfg.crashFile}do os.remove(p)end

dofile("main.lua")
assert(gpu.res[1]==80 and gpu.res[2]==25,"terminal resolution restored after crash")
assert(clears>=1,"terminal cleanup did not run")
assert(pulls==1,"crash screen must wait for one acknowledgement event")
local f=assert(io.open(cfg.crashFile,"r"));local report=f:read("*a");f:close()
assert(report:find("forced GPU crash",1,true),"persistent crash report missing root cause")
for _,p in ipairs{cfg.dataFile,cfg.dataFile..".bak",cfg.logFile,cfg.crashFile}do os.remove(p)end
print("MAIN CRASH SIMULATION PASSED")
