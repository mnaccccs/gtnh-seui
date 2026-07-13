-- Full main.lua simulation smoke test with mocked OpenComputers runtime
package.path="./?.lua;./?/init.lua;"..package.path
if not table.pack then function table.pack(...) return {n=select('#',...),...} end end
local now=0
local pulls=0
package.preload["sides"]=function()return{down=0,up=1,north=2,south=3,west=4,east=5}end
package.preload["computer"]=function()return{uptime=function()now=now+.1 return now end,freeMemory=function()return 1024*1024 end}end
local function strictWtrunc(s,n)local w,e=0,0;while w<n do if e>=#s then error("index "..e..", length "..#s)end;w=w+1;e=e+1 end;return e>1 and s:sub(1,e-1)or""end
package.preload["unicode"]=function()return{wlen=function(s)return #s end,wtrunc=strictWtrunc,char=function(n)return string.char(n)end}end
local gpu={address="gpu",fg=0xffffff,bg=0,res={80,25}}
function gpu.getForeground()return gpu.fg,false end; function gpu.getBackground()return gpu.bg,false end
function gpu.setForeground(v)gpu.fg=v return v end; function gpu.setBackground(v)gpu.bg=v return v end
function gpu.getResolution()return gpu.res[1],gpu.res[2]end; function gpu.setResolution(w,h)gpu.res={w,h}return true end
function gpu.setDepth()return 8 end; function gpu.bind()return true end; function gpu.fill()return true end; function gpu.set()return true end
local screen={address="screen",setTouchModeInverted=function()return false end,setPrecise=function()return false end}
local function emptyIter() return function() return nil end end
package.preload["component"]=function()return{gpu=gpu,screen=screen,list=function()return emptyIter()end,proxy=function()end,methods=function()return{}end}end
package.preload["event"]=function()return{pull=function(timeout)pulls=pulls+1;if pulls>=3 then return "interrupted" end return nil end}end
package.preload["term"]=function()return{clear=function()end}end
package.preload["shell"]=function()return{parse=function()return {},{simulate=true}end}end
package.preload["filesystem"]=function()return{
 path=function(p)return "."end, exists=function(p)local f=io.open(p,"r");if f then f:close()return true end return false end,
 makeDirectory=function()return true end, remove=function(p)return os.remove(p)end, rename=function(a,b)return os.rename(a,b)end,
}end
package.preload["serialization"]=function()return{serialize=function()return"{}"end,deserialize=function()return{}end}end
local realConfig=dofile("config.lua")
realConfig.dataFile="./tests/.tmp-seui.dat";realConfig.logFile="./tests/.tmp-seui.log"
package.preload["config"]=function()return realConfig end
os.remove(realConfig.dataFile);os.remove(realConfig.dataFile..".bak");os.remove(realConfig.logFile)
dofile("main.lua")
assert(gpu.res[1]==80 and gpu.res[2]==25,"terminal resolution restored")
os.remove(realConfig.dataFile);os.remove(realConfig.dataFile..".bak");os.remove(realConfig.logFile)
print("MAIN SIMULATION PASSED")
