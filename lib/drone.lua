-- SEUI lib/drone.lua
-- 太空采矿模块无人机供应后端

local log = require("lib.log")

local M = {}

local DRONE_ITEM = "gtnhintergalactic:item.MiningDrone"

local function validateSides(config)
  local droneSide = tonumber(config.droneSide)
  local inputSide = tonumber(config.inputSide)
  if not droneSide or not inputSide or droneSide < 0 or droneSide > 5 or inputSide < 0 or inputSide > 5 then
    return nil, nil, "droneSide/inputSide 必须是 sides 的 0..5 方向值"
  end
  if droneSide == inputSide then
    return nil, nil, "droneSide 与 inputSide 不能相同"
  end
  return droneSide, inputSide
end

local function readStacks(transposer, side)
  local ok, iter = pcall(transposer.getAllStacks, side)
  if not ok or not iter then return nil, "无法读取无人机库存" end
  local ok2, stacks = pcall(iter.getAll)
  if not ok2 or type(stacks) ~= "table" then return nil, "无人机库存迭代失败" end
  return stacks
end

local function findFleetDroneSlot(stacks, tier, required, allowRandom)
  -- 与 Wiki 原程序一致：只从第一只转运器读取一次共享末影箱，记住槽位和数量，
  -- 随后所有转运器都从同一槽位各取 1 个。不能在每次转移后重读其他转运器的
  -- getAllStacks；同频道末影箱的远端视图可能延迟一拍，正是此前误报“库存发生变化”的原因。
  for slot, stack in pairs(stacks) do
    if stack and stack.name == DRONE_ITEM
        and tonumber(stack.damage or -1) == tier - 1
        and (tonumber(stack.size) or 0) >= required then
      return tonumber(slot) + 1, tonumber(stack.size), tier, false
    end
  end
  if allowRandom then
    for slot, stack in pairs(stacks) do
      if stack and stack.name == DRONE_ITEM and (tonumber(stack.size) or 0) >= required then
        return tonumber(slot) + 1, tonumber(stack.size), (tonumber(stack.damage) or 0) + 1, true
      end
    end
  end
  return nil, 0, nil, false
end

-- Wiki 同步模式：所有矿机追同一目标，所有转运器方向一致、连接同频道末影箱。
-- 该函数一次完成整个矿机组的无人机退回与重新分发；调用方必须先确认所有矿机均已停稳。
local function prepareTransposerFleet(assignment, config, hw)
  local transposers = hw.transposers or {}
  if #transposers == 0 then return false, "未发现 transposer" end
  if hw.miners and #hw.miners > 0 and #transposers ~= #hw.miners then
    return false, string.format("矿机/转运器数量不一致：miners=%d transposers=%d", #hw.miners, #transposers)
  end

  local droneSide, inputSide, sideErr = validateSides(config)
  if not droneSide then return false, sideErr end
  local tier = tonumber(assignment.params and assignment.params.droneTier) or 1

  -- 先统一退回旧无人机。输入总线为空时 moved=0 不是故障，但调用异常必须失败。
  for _, transposer in ipairs(transposers) do
    local ok, err = pcall(transposer.proxy.transferItem, inputSide, droneSide)
    if not ok then return false, "退回旧无人机失败: " .. tostring(err) end
  end

  -- 按 Wiki 布局，只读取第一只转运器看到的共享末影箱，并固定一个目标等级槽位。
  local firstStacks, firstErr = readStacks(transposers[1].proxy, droneSide)
  if not firstStacks then return false, firstErr end
  local selectedSlot, available, selectedTier, random = findFleetDroneSlot(
    firstStacks, tier, #transposers, config.allowRandomDrone)
  if not selectedSlot then
    return false, string.format("MK-%d 采矿无人机不足：同一堆至少需要%d个", tier, #transposers)
  end
  if random then
    log.warn("drone", string.format("MK-%d 不足，整个矿机组统一改用 MK-%d", tier, selectedTier))
  end

  -- 所有矿机严格各取一个、且全部来自同一槽，因此不会混入箱内另一等级的无人机。
  local remaining = available
  for _, transposer in ipairs(transposers) do
    if remaining <= 0 then return false, "无人机计数耗尽" end
    local ok, moved = pcall(transposer.proxy.transferItem, droneSide, inputSide, 1, selectedSlot)
    if not ok or not moved or tonumber(moved) < 1 then
      return false, "无人机转移失败: " .. tostring(moved)
    end
    remaining = remaining - 1
  end

  log.info("drone", string.format("已向 %d 台矿机各分发 1 个 MK-%d 无人机（共享槽位%d）",
    #transposers, selectedTier, selectedSlot))
  return true
end

local function prepareME(assignment, config, hw)
  local tier = tonumber(assignment.params and assignment.params.droneTier) or 1
  local mapping = (config.droneDatabaseSlots or {})[tier]
  if not mapping or not mapping[1] or not mapping[2] then
    return false, "droneDatabaseSlots 未配置 MK-" .. tostring(tier)
  end
  if not hw.database then return false, "database 不在线" end
  if not hw.meInterface then return false, "me_interface 不在线" end
  local me = hw.meInterface.proxy
  if not me.setInterfaceConfiguration then
    return false, "选定 me_interface 没有 setInterfaceConfiguration"
  end

  local ok1, err1 = pcall(me.setInterfaceConfiguration, 1, hw.database.address, mapping[1], 64)
  if not ok1 then return false, tostring(err1) end
  local ok2, err2 = pcall(me.setInterfaceConfiguration, 2, hw.database.address, mapping[2], 64)
  if not ok2 then return false, tostring(err2) end
  return true
end

function M.backend(assignment, config)
  if not assignment or assignment.domain ~= "miner" then return "none" end
  return (assignment.target.route and assignment.target.route.droneBackend) or config.droneBackend
end

function M.prepare(assignment, config, hw)
  if not assignment or assignment.domain ~= "miner" then return true end
  local backend = M.backend(assignment, config)
  if backend == "transposer" then
    return prepareTransposerFleet(assignment, config, hw)
  elseif backend == "me_interface" then
    return prepareME(assignment, config, hw)
  elseif backend == "manual" then
    return true
  end
  return false, "未知无人机后端: " .. tostring(backend)
end

return M
