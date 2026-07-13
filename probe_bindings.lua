-- SEUI 转运器方向只读探针
-- 用法：在 OpenOS 中运行 `lua probe_bindings.lua`
-- 不会转移物品、修改参数或启停机器。

local component = require("component")

local SIDE_NAMES = {
  [0] = "down/bottom",
  [1] = "up/top",
  [2] = "north/back",
  [3] = "south/front",
  [4] = "west/right",
  [5] = "east/left",
}

local SIDE_LUA = {
  [0] = "sides.down",
  [1] = "sides.up",
  [2] = "sides.north",
  [3] = "sides.south",
  [4] = "sides.west",
  [5] = "sides.east",
}

local DRONE_ITEM = "gtnhintergalactic:item.MiningDrone"

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return false, "method unavailable" end
  return pcall(fn, ...)
end

local function sortedComponents(ctype)
  local out = {}
  for address in component.list(ctype) do
    out[#out + 1] = address
  end
  table.sort(out)
  return out
end

local function stackSummary(transposer, side)
  local okIter, iter = safeCall(transposer.getAllStacks, side)
  if not okIter or not iter then return "" end
  local okAll, stacks = safeCall(iter.getAll)
  if not okAll or type(stacks) ~= "table" then return "" end

  local drones = {}
  local samples = {}
  for _, stack in pairs(stacks) do
    if stack and (tonumber(stack.size) or 0) > 0 then
      local name = tostring(stack.name or stack.label or "?")
      if name == DRONE_ITEM then
        local tier = (tonumber(stack.damage) or 0) + 1
        drones[tier] = (drones[tier] or 0) + (tonumber(stack.size) or 0)
      elseif #samples < 3 then
        samples[#samples + 1] = tostring(stack.label or name)
      end
    end
  end

  local parts = {}
  local tiers = {}
  for tier in pairs(drones) do tiers[#tiers + 1] = tier end
  table.sort(tiers)
  for _, tier in ipairs(tiers) do
    parts[#parts + 1] = string.format("MK-%d无人机×%d", tier, drones[tier])
  end
  if #samples > 0 then
    parts[#parts + 1] = "样本物品=" .. table.concat(samples, ",")
  end
  return table.concat(parts, "；")
end

local miners = {}
for address in component.list("gt_machine") do
  local proxy = component.proxy(address)
  local ok, name = safeCall(proxy.getName)
  name = ok and tostring(name or "") or "<getName失败>"
  if name:match("projectmoduleminer") then
    miners[#miners + 1] = { address = address, name = name }
  end
end
table.sort(miners, function(a, b) return a.address < b.address end)

local transposers = sortedComponents("transposer")

print("SEUI 转运器方向只读探针")
print(string.rep("=", 72))
print("太空矿机（仅用于核对数量，无需手动绑定地址）：")
if #miners == 0 then print("  未发现 projectmoduleminer") end
for i, miner in ipairs(miners) do
  print(string.format("  [%d] %s  %s", i, miner.address, miner.name))
end

print(string.rep("=", 72))
print("转运器及其六个相邻面：")
if #transposers == 0 then print("  未发现 transposer") end
for i, address in ipairs(transposers) do
  local transposer = component.proxy(address)
  print(string.format("  转运器[%d] %s", i, address))
  for side = 0, 5 do
    local okSize, size = safeCall(transposer.getInventorySize, side)
    if okSize and type(size) == "number" then
      local okName, name = safeCall(transposer.getInventoryName, side)
      local invName = okName and tostring(name or "?") or "?"
      local summary = stackSummary(transposer, side)
      if summary ~= "" then summary = "  " .. summary end
      print(string.format("    %-13s = %d  库存=%s  槽位=%d%s",
        SIDE_LUA[side], side, invName, size, summary))
    else
      print(string.format("    %-13s = %d  无库存", SIDE_LUA[side], side))
    end
  end
end

print(string.rep("=", 72))
print("方向说明：方向以转运器位置为中心，采用世界方向；down=0, up=1, north=2, south=3, west=4, east=5。")
print("droneSide 指向共享无人机仓；inputSide 指向矿机的无人机输入库存/输入总线。")
print("识别办法：共享仓放一架无人机，矿机输入侧放一个容易辨认的标记物，再运行本探针。")
print("程序按 Wiki 方案统一控制所有转运器，不需要判断转运器与矿机的对应关系。")
print(string.rep("=", 72))
print("config.lua 模板：")
print('local sides = require("sides")')
print("droneSide = sides.down, -- 所有转运器朝共享无人机末影箱的一侧")
print("inputSide = sides.up,   -- 所有转运器朝矿机输入总线的一侧")
