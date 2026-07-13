-- SEUI lib/controller.lua
-- 每台机器一个非阻塞、安全写后读回的控制状态机

local computer = require("computer")
local log = require("lib.log")
local drone = require("lib.drone")

local M = {}
local workers = {} -- address -> state

local function assignmentSignature(a)
  if not a then return nil end
  local p = a.params or {}
  return table.concat({
    tostring(a.domain), tostring(a.target and a.target.id),
    tostring(p.planetType), tostring(p.gasType), tostring(p.distance),
    tostring(p.droneTier), tostring(a.batch), tostring(a.recipe)
  }, "|")
end

local function newWorker(machine, domain)
  return {
    address = machine.address,
    proxy = machine.proxy,
    name = machine.name or "",
    domain = domain,
    threads = machine.threads or 1,
    paramBackend = machine.paramBackend or "unsupported",
    phase = "IDLE",
    enteredAt = computer.uptime(),
    deadline = 0,
    lastError = nil,
    servingTarget = nil,
    activeSignature = nil,
    pendingAssignment = nil,
  }
end

-- 与新硬件快照同步；同地址状态保留，避免周期重扫导致无意义停机。
function M.init(hw, config)
  local old = workers
  local nextWorkers = {}
  local count = 0

  for _, machine in ipairs(hw.pumps or {}) do
    local w = old[machine.address] or newWorker(machine, "pump")
    w.proxy, w.name, w.domain = machine.proxy, machine.name, "pump"
    w.threads = machine.threads or 1
    w.paramBackend = machine.paramBackend or "unsupported"
    nextWorkers[machine.address] = w
    count = count + 1
  end
  for _, machine in ipairs(hw.miners or {}) do
    local w = old[machine.address] or newWorker(machine, "miner")
    w.proxy, w.name, w.domain = machine.proxy, machine.name, "miner"
    w.threads = 1
    w.paramBackend = machine.paramBackend or "unsupported"
    nextWorkers[machine.address] = w
    count = count + 1
  end

  -- 消失的机器不能再调用，但记录告警。
  for address, _ in pairs(old) do
    if not nextWorkers[address] then
      log.warn("controller", "机器离线: " .. address)
    end
  end
  workers = nextWorkers
  log.info("controller", "同步 " .. count .. " 台机器")
end

local function transition(w, phase, now)
  w.phase = phase
  w.enteredAt = now or computer.uptime()
end

function M.enqueue(assignment)
  if not assignment or not assignment.worker or not assignment.target then
    return false, "invalid assignment"
  end
  local w = workers[assignment.worker.address]
  if not w then return false, "worker not found" end

  local sig = assignmentSignature(assignment)
  if w.phase == "RUNNING" and sig == w.activeSignature then
    return true -- 已经执行相同任务，不重复停机/写参
  end
  if w.pendingAssignment and sig == assignmentSignature(w.pendingAssignment) then
    return true -- 已经排队
  end

  w.pendingAssignment = assignment
  if w.phase == "IDLE" then
    transition(w, "REQUEST_STOP")
  elseif w.phase == "RUNNING" then
    transition(w, "REQUEST_STOP")
  elseif w.phase == "REQUEST_END" then
    -- 等待停完后会处理 pending
  elseif w.phase == "FAULT" then
    -- 保留任务，必须人工 Retry 才会继续
    return false, "worker is faulted"
  end
  return true
end

function M.stopDomain(domain, reason)
  for _, w in pairs(workers) do
    if w.domain == domain then
      w.pendingAssignment = nil
      if w.phase == "RUNNING" or w.phase == "START" then
        transition(w, "REQUEST_END")
        log.info("controller", w.address:sub(1, 8) .. " 停止 " .. domain .. ": " .. tostring(reason))
      end
    end
  end
end

local function applyParams(w, backend)
  local a = w.pendingAssignment
  if not a then return true end
  local p = a.params or {}
  local proxy = w.proxy

  if backend == "keyed" then
    if a.domain == "pump" then
      -- 兼容模式：该模块全部 recipe 线程追同一目标。
      for recipe = 0, (w.threads or 1) - 1 do
        local ok1, err1 = pcall(proxy.setParameter, "recipe" .. recipe .. ".planetType", p.planetType or 0)
        if not ok1 then return false, err1 end
        local ok2, err2 = pcall(proxy.setParameter, "recipe" .. recipe .. ".gasType", p.gasType or 0)
        if not ok2 then return false, err2 end
      end
      if a.batch then
        local ok3, err3 = pcall(proxy.setParameter, "batch", a.batch)
        if not ok3 then return false, err3 end
      end
    else
      local ok, err = pcall(proxy.setParameter, "distance", p.distance or 0)
      if not ok then return false, err end
      if p.parallel ~= nil then
        local ok2, err2 = pcall(proxy.setParameter, "parallel", p.parallel)
        if not ok2 then return false, err2 end
      end
    end
    return true
  end

  if backend == "legacy" then
    if a.domain == "pump" then
      for i = 0, 6, 2 do
        local ok1, err1 = pcall(proxy.setParameters, i, 0, p.planetType or 0)
        if not ok1 then return false, err1 end
        local ok2, err2 = pcall(proxy.setParameters, i, 1, p.gasType or 0)
        if not ok2 then return false, err2 end
      end
      if a.batch then
        local ok3, err3 = pcall(proxy.setParameters, 9, 1, a.batch)
        if not ok3 then return false, err3 end
      end
    else
      local ok, err = pcall(proxy.setParameters, 0, 0, p.distance or 0)
      if not ok then return false, err end
    end
    return true
  end

  return false, "unsupported parameter backend"
end

local function verifyParams(w, backend)
  local a = w.pendingAssignment
  if not a then return true end
  if backend == "legacy" then
    -- beta1 旧接口无统一可依赖的读回方法；UI 会明确标为 legacy。
    log.warn("controller", w.address:sub(1, 8) .. " legacy 后端无法可靠读回")
    return true
  end
  if backend ~= "keyed" then return false, "unsupported parameter backend" end

  local ok, values = pcall(w.proxy.getParameters)
  if not ok or type(values) ~= "table" then return false, "getParameters failed" end
  local p = a.params or {}

  if a.domain == "pump" then
    for recipe = 0, (w.threads or 1) - 1 do
      local kp = "recipe" .. recipe .. ".planetType"
      local kg = "recipe" .. recipe .. ".gasType"
      if tonumber(values[kp]) ~= tonumber(p.planetType) then
        return false, kp .. " mismatch: " .. tostring(values[kp])
      end
      if tonumber(values[kg]) ~= tonumber(p.gasType) then
        return false, kg .. " mismatch: " .. tostring(values[kg])
      end
    end
    if a.batch and tonumber(values.batch) ~= tonumber(a.batch) then
      return false, "batch mismatch: " .. tostring(values.batch)
    end
  else
    if tonumber(values.distance) ~= tonumber(p.distance) then
      return false, "distance mismatch: " .. tostring(values.distance)
    end
    if p.parallel ~= nil and tonumber(values.parallel) ~= tonumber(p.parallel) then
      return false, "parallel mismatch: " .. tostring(values.parallel)
    end
  end
  return true
end

local function fail(w, message, now)
  w.lastError = tostring(message)
  transition(w, "FAULT", now)
  pcall(w.proxy.setWorkAllowed, false)
  log.error("controller", w.address:sub(1, 8) .. " FAULT: " .. w.lastError)
end

local function droneBackend(assignment, config)
  if type(drone.backend) == "function" then
    return drone.backend(assignment, config)
  end
  if not assignment or assignment.domain ~= "miner" then return "none" end
  return (assignment.target.route and assignment.target.route.droneBackend) or config.droneBackend
end

local function sameFleetTask(a, b)
  if not a or not b then return false end
  local ap, bp = a.params or {}, b.params or {}
  return tostring(a.target and a.target.id) == tostring(b.target and b.target.id)
      and tonumber(ap.droneTier) == tonumber(bp.droneTier)
end

-- transposer 后端采用 Wiki 的全体同步方式。只要任一矿机需要换目标，就把其余矿机
-- 一并停稳；所有矿机均进入 PREPARE 后只调用一次 drone.prepare，再同时进入 APPLY。
local function advanceMinerFleetPrepare(now, config, hw)
  local leader = nil
  for _, w in pairs(workers) do
    if w.domain == "miner" and w.phase == "PREPARE" and w.pendingAssignment
        and droneBackend(w.pendingAssignment, config) == "transposer" then
      leader = w
      break
    end
  end
  if not leader then return end

  local assignment = leader.pendingAssignment
  local allReady, peerFault = true, false
  for _, w in pairs(workers) do
    if w.domain == "miner" then
      if w.phase == "FAULT" then
        peerFault = true
      elseif not w.pendingAssignment then
        -- 可能是仍在运行相同任务的旧矿机，或硬件重扫后新加入的矿机。
        -- 为保证全局换无人机时没有任何矿机在工作，将它纳入同一次任务。
        w.pendingAssignment = assignment
        if w.phase == "RUNNING" or w.phase == "IDLE" then
          transition(w, "REQUEST_STOP", now)
        end
        allReady = false
      elseif droneBackend(w.pendingAssignment, config) ~= "transposer"
          or not sameFleetTask(w.pendingAssignment, assignment) then
        fail(w, "矿机组存在不一致的无人机任务", now)
        peerFault = true
      elseif w.phase ~= "PREPARE" then
        allReady = false
      end
    end
  end

  if peerFault then
    for _, w in pairs(workers) do
      if w.domain == "miner" and w.phase ~= "FAULT" then
        fail(w, "矿机组内其他机器故障，取消同步换无人机", now)
      end
    end
    return
  end
  if not allReady then return end

  local ok, err = drone.prepare(assignment, config, hw)
  if not ok then
    for _, w in pairs(workers) do
      if w.domain == "miner" and w.phase == "PREPARE" then
        fail(w, "PREPARE: " .. tostring(err), now)
      end
    end
    return
  end
  for _, w in pairs(workers) do
    if w.domain == "miner" and w.phase == "PREPARE" then
      transition(w, "APPLY", now)
    end
  end
end

function M.tick(now, config, hw)
  local idleTimeout = config.idleTimeout or 30
  advanceMinerFleetPrepare(now, config, hw)
  for _, w in pairs(workers) do
    local backend = w.paramBackend or hw.paramBackend or "unsupported"
    if w.phase == "REQUEST_STOP" or w.phase == "REQUEST_END" then
      local ending = w.phase == "REQUEST_END"
      local ok, err = pcall(w.proxy.setWorkAllowed, false)
      if not ok then
        fail(w, "setWorkAllowed(false): " .. tostring(err), now)
      else
        w.stopOnly = ending and w.pendingAssignment == nil
        w.deadline = now + idleTimeout
        transition(w, "WAIT_IDLE", now)
      end

    elseif w.phase == "WAIT_IDLE" then
      local ok, active = pcall(w.proxy.isMachineActive)
      if not ok then
        fail(w, "isMachineActive: " .. tostring(active), now)
      elseif not active then
        if w.pendingAssignment then
          transition(w, "PREPARE", now)
        else
          w.servingTarget, w.activeSignature = nil, nil
          transition(w, "IDLE", now)
        end
      elseif now > w.deadline then
        fail(w, "WAIT_IDLE timeout " .. idleTimeout .. "s", now)
      end

    elseif w.phase == "PREPARE" then
      if droneBackend(w.pendingAssignment, config) ~= "transposer" then
        local ok, err = drone.prepare(w.pendingAssignment, config, hw)
        if not ok then fail(w, "PREPARE: " .. tostring(err), now)
        else transition(w, "APPLY", now) end
      end -- transposer 后端由 advanceMinerFleetPrepare 统一推进

    elseif w.phase == "APPLY" then
      local ok, err = applyParams(w, backend)
      if not ok then fail(w, "APPLY: " .. tostring(err), now)
      else transition(w, "VERIFY", now) end

    elseif w.phase == "VERIFY" then
      local ok, err = verifyParams(w, backend)
      if not ok then fail(w, "VERIFY: " .. tostring(err), now)
      else transition(w, "START", now) end

    elseif w.phase == "START" then
      local ok, err = pcall(w.proxy.setWorkAllowed, true)
      if not ok then
        fail(w, "setWorkAllowed(true): " .. tostring(err), now)
      else
        local a = w.pendingAssignment
        w.servingTarget = a.target.id
        w.activeSignature = assignmentSignature(a)
        w.pendingAssignment = nil
        w.lastError = nil
        if a.target.runtime then a.target.runtime.lastServed = now end
        transition(w, "RUNNING", now)
        log.info("controller", w.address:sub(1, 8) .. " RUNNING " .. w.servingTarget)
      end
    end
  end
end

function M.retry(address)
  local w = workers[address]
  if not w or w.phase ~= "FAULT" then return false end
  w.lastError = nil
  transition(w, "REQUEST_STOP")
  return true
end

function M.stopAll(reason)
  log.warn("controller", "STOP ALL: " .. tostring(reason))
  for _, w in pairs(workers) do
    pcall(w.proxy.setWorkAllowed, false)
    w.pendingAssignment = nil
    w.servingTarget = nil
    w.activeSignature = nil
    w.lastError = "STOP ALL: " .. tostring(reason)
    transition(w, "FAULT")
  end
end

function M.status()
  local result = {}
  for address, w in pairs(workers) do
    result[address] = {
      phase = w.phase,
      domain = w.domain,
      servingTarget = w.servingTarget,
      pendingTarget = w.pendingAssignment and w.pendingAssignment.target.id or nil,
      hasPending = w.pendingAssignment ~= nil,
      lastError = w.lastError,
    }
  end
  return result
end

function M.getAllWorkers() return workers end
function M.getWorker(address) return workers[address] end

return M
