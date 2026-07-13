-- SEUI main.lua
-- 太空电梯双业务 UI 主入口
-- GTNH 2.9.0-beta-1 / OpenComputers 1.12.44-GTNH
-- Lua 5.2/5.3 双兼容

local component = require("component")
local computer = require("computer")
local event = require("event")
local os = require("os")
local filesystem = require("filesystem")

-- OpenOS 的 package.path 包含 ./，但用户可能从任意目录运行 /seui/main.lua。
-- process.load 会把当前程序绝对路径写入环境变量 _，据此补入脚本目录。
local runningProgram = os.getenv("_")
if runningProgram then
  local baseDir = filesystem.path(runningProgram)
  package.path = baseDir .. "?.lua;" .. baseDir .. "?/init.lua;" .. package.path
end

-- 加载模块
local config = require("config")
local log = require("lib.log")
local store = require("lib.store")
local discovery = require("lib.discovery")
local inventory = require("lib.inventory")
local model = require("lib.model")
local fluidCatalog = require("lib.fluid_catalog")
local scheduler = require("lib.scheduler")
local controller = require("lib.controller")
local ui = require("lib.ui")

-- ========== 应用状态 ==========
local app = {
  running = true,
  mode = "readonly",        -- "simulate" / "readonly" / "control"
  hw = nil,                 -- 硬件快照
  nextInventoryScan = 0,
  nextHardwareRescan = 0,
  nextTargetRescan = 0,
  nextSchedule = 0,
  needRescan = false,
  needImport = false,
  configDirty = false,
  lastSaveTime = 0,
  lastSaveAttempt = -math.huge,
  config = config,
}

-- ========== 解析命令行参数 ==========
local shell = require("shell")
local args, opts = shell.parse(...)

if opts.simulate then
  app.mode = "simulate"
elseif opts.control then
  app.mode = "control"
else
  app.mode = "readonly"
end
config.runtimeMode = app.mode

-- ========== 初始化 ==========
local function initLog()
  log.init(config.logFile, config.logMaxSize, config.logKeep)
  log.info("main", "=== SEUI 启动 === mode=" .. app.mode)
end

local function initStore()
  store.init(config.dataFile)
end

local function loadOrCreateConfig()
  local data, err = store.load()
  if data then
    data = store.migrate(data)
    -- 合并存储的配置到运行时
    if data.ui then
      ui.setState(data.ui)
    end
    if data.targets and #data.targets > 0 then
      for _, t in ipairs(data.targets) do
        model.addTarget(t)
      end
    end
    fluidCatalog.populate(model)
    log.info("main", "从配置加载 " .. #model.getTargets() .. " 个目标")
  else
    log.info("main", "无配置文件: " .. tostring(err))
    fluidCatalog.populate(model)
  end
end

local function injectSimulatedData()
  -- 模拟模式：注入假数据
  local fluids = {
    {label = "氢气", fluid = "hydrogen", planet = 8, gas = 1},
    {label = "氦气", fluid = "helium", planet = 5, gas = 4},
    {label = "氧气", fluid = "oxygen", planet = 7, gas = 4},
    {label = "氮气", fluid = "nitrogen", planet = 7, gas = 3},
    {label = "氟", fluid = "fluorine", planet = 7, gas = 2},
    {label = "氚", fluid = "tritium", planet = 6, gas = 2},
    {label = "氘", fluid = "deuterium", planet = 6, gas = 1},
    {label = "氦-3", fluid = "helium-3", planet = 5, gas = 2},
    {label = "氙", fluid = "xenon", planet = 6, gas = 4},
    {label = "氪", fluid = "krypton", planet = 5, gas = 8},
    {label = "氖", fluid = "neon", planet = 5, gas = 6},
    {label = "氩", fluid = "argon", planet = 5, gas = 7},
    {label = "氡", fluid = "radon", planet = 8, gas = 6},
    {label = "甲烷", fluid = "methane", planet = 5, gas = 9},
    {label = "氨气", fluid = "ammonia", planet = 6, gas = 3},
    {label = "乙烯", fluid = "ethylene", planet = 6, gas = 5},
    {label = "乙烷", fluid = "ethane", planet = 5, gas = 11},
    {label = "一氧化碳", fluid = "carbon_monoxide", planet = 5, gas = 1},
    {label = "二氧化碳", fluid = "carbon_dioxide", planet = 4, gas = 8},
    {label = "硫化氢", fluid = "hydrogen_sulfide", planet = 5, gas = 10},
    {label = "氟化氢", fluid = "hydrofluoric_acid", planet = 7, gas = 1},
    {label = "硫酸", fluid = "sulfuric_acid", planet = 4, gas = 1},
    {label = "盐水", fluid = "salt_water", planet = 5, gas = 3},
    {label = "蒸馏水", fluid = "distilled_water", planet = 8, gas = 5},
    {label = "熔融铁", fluid = "molten_iron", planet = 4, gas = 2},
    {label = "熔融铜", fluid = "molten_copper", planet = 8, gas = 3},
    {label = "熔融锡", fluid = "molten_tin", planet = 8, gas = 7},
    {label = "熔融铅", fluid = "molten_lead", planet = 4, gas = 5},
    {label = "氯苯", fluid = "chlorobenzene", planet = 2, gas = 1},
    {label = "末影黏液", fluid = "ender_goo", planet = 3, gas = 1},
    {label = "岩浆", fluid = "lava", planet = 3, gas = 3},
    {label = "天然气", fluid = "natural_gas", planet = 3, gas = 4},
    {label = "石油", fluid = "oil", planet = 4, gas = 3},
    {label = "重油", fluid = "heavy_oil", planet = 4, gas = 4},
    {label = "轻油", fluid = "light_oil", planet = 4, gas = 7},
    {label = "原油", fluid = "raw_oil", planet = 4, gas = 6},
    {label = "液态空气", fluid = "liquid_air", planet = 8, gas = 2},
    {label = "液氧", fluid = "liquid_oxygen", planet = 5, gas = 5},
    {label = "未知液体", fluid = "unknown_liquid", planet = 8, gas = 4},
    {label = "硅烷", fluid = "silane", planet = 2, gas = 2},
  }

  for i, f in ipairs(fluids) do
    model.addTarget({
      id = "fluid:" .. f.fluid,
      domain = "pump",
      label = f.label,
      fluid = f.fluid,
      mode = "TARGET",
      target = 10e9,
      current = math.random(0, 15e9),
      weight = 0,
      order = i,
      route = { planetType = f.planet, gasType = f.gas, maxBatch = 30 },
    })
  end

  -- 矿物假数据
  local ores = {
    {label = "铁锭", name = "minecraft:iron_ingot", damage = 0},
    {label = "金锭", name = "minecraft:gold_ingot", damage = 0},
    {label = "铜锭", name = "gregtech:gt.metaitem.01", damage = 12000},
    {label = "锡锭", name = "gregtech:gt.metaitem.01", damage = 13000},
  }
  for i, o in ipairs(ores) do
    model.addTarget({
      id = "item:" .. o.name .. ":" .. o.damage,
      domain = "miner",
      label = o.label,
      item = { name = o.name, damage = o.damage },
      mode = "TARGET",
      target = 1e9,
      current = math.random(0, 15e8),
      weight = 0,
      order = i,
      route = { droneTier = 8, distance = 100 },
    })
  end

  log.info("main", "模拟模式：注入 " .. #fluids .. " 流体 + " .. #ores .. " 矿物")
end

local function initUI()
  local gpu = component.gpu
  local screen = component.screen or nil
  if not gpu then
    error("未找到 GPU 组件")
  end
  ui.init(gpu, screen, config)
end

-- ========== 扫描 ==========

local function doHardwareScan()
  log.info("main", "开始硬件扫描...")
  app.hw = discovery.scan()

  if app.mode ~= "simulate" then
    controller.init(app.hw, config)
  end

  -- 初始目录已有 40 个 OFF 流体；首次启动仍需自动导入请求器中的启用目标。
  local hasImported = false
  for _, t in ipairs(model.getTargets()) do
    if t.sourceRef then hasImported = true break end
  end
  if not hasImported and #app.hw.levelMaintainers > 0 then
    local n = model.importFromMaintainers(app.hw.levelMaintainers, config.importProfile)
    if n > 0 then app.configDirty = true end
  end

  ui.markDirty()
end

local function doInventoryScan()
  if app.mode == "simulate" then
    -- 模拟模式不扫描真实库存
    return
  end

  ui.setScanning(true)
  local fluidProxy = app.hw.fluidInterface and app.hw.fluidInterface.proxy or nil
  local meProxy = app.hw.meInterface and app.hw.meInterface.proxy or nil
  local minerTargets = model.getByDomain("miner")

  inventory.scan(fluidProxy, meProxy, minerTargets)

  -- 更新所有目标的当前库存
  local snap = inventory.getSnapshot()
  local targets = model.getTargets()
  for _, t in ipairs(targets) do
    model.updateCurrent(t, snap)
  end

  ui.setScanning(false)
  ui.markDirty()
end

-- ========== 调度与控制 ==========

local function doSchedule()
  if app.mode == "simulate" or app.mode == "readonly" then
    return
  end

  if app.mode == "control" then
    local now = computer.uptime()
    local pumpFresh = inventory.isFresh(now, config.maxSnapshotAge, "pump")
    local minerFresh = inventory.isFresh(now, config.maxSnapshotAge, "miner")

    -- PUMP 调度
    if pumpFresh then
      local pumpTargets = model.getByDomain("pump")
      local pumpAssignments = scheduler.plan("pump", pumpTargets, app.hw.pumps, now, config)
      if pumpAssignments then
        for _, a in ipairs(pumpAssignments) do controller.enqueue(a) end
      else
        controller.stopDomain("pump", "all targets satisfied")
      end
    else
      log.warn("main", "流体快照过期，停止 PUMP 新派工")
      if config.failClosed then controller.stopDomain("pump", "stale inventory") end
    end

    -- MINER 调度
    if minerFresh then
      local minerTargets = model.getByDomain("miner")
      local minerAssignments = scheduler.plan("miner", minerTargets, app.hw.miners, now, config)
      if minerAssignments then
        for _, a in ipairs(minerAssignments) do controller.enqueue(a) end
      else
        controller.stopDomain("miner", "all targets satisfied")
      end
    else
      log.warn("main", "物品快照过期，停止 MINER 新派工")
      if config.failClosed then controller.stopDomain("miner", "stale inventory") end
    end
  end
end

-- ========== 状态推导 ==========

local function updateTargetStates()
  local now = computer.uptime()
  local ws = controller.status()
  local targets = model.getTargets()

  for _, t in ipairs(targets) do
    -- 检查是否有机器正在服务此目标
    local machineActive = false
    local hasPendingTask = false
    for addr, w in pairs(ws) do
      if w.servingTarget == t.id or w.pendingTarget == t.id then
        if w.phase == "RUNNING" then
          machineActive = true
        end
        if w.hasPending then
          hasPendingTask = true
        end
      end
    end

    -- 只为当前页面所属 domain 的目标推导状态
    local fresh = app.mode == "simulate" or inventory.isFresh(now, config.maxSnapshotAge, t.domain)
    model.deriveState(t, fresh, machineActive, hasPendingTask)
  end
end

-- ========== 配置保存 ==========

local function saveConfig(force)
  if not app.configDirty then return end
  local now = computer.uptime()
  if not force and now - app.lastSaveAttempt < 5 then return end
  app.lastSaveAttempt = now

  local data = {
    schemaVersion = 1,
    ui = ui.getState(),
    scheduler = {
      scanInterval = config.scanInterval,
      failClosed = config.failClosed,
    },
    targets = {},
  }

  for _, t in ipairs(model.getTargets()) do
    table.insert(data.targets, {
      id = t.id,
      domain = t.domain,
      label = t.label,
      item = t.item,
      fluid = t.fluid,
      fluidAliases = t.fluidAliases,
      mode = t.mode,
      target = t.target,
      weight = t.weight,
      order = t.order,
      lowRatio = t.lowRatio,
      highRatio = t.highRatio,
      minDwell = t.minDwell,
      route = t.route,
      sourceRef = t.sourceRef,
    })
  end

  local ok, err = store.saveAtomic(data)
  if ok then
    app.configDirty = false
    app.lastSaveTime = now
  else
    log.error("main", "配置保存失败: " .. tostring(err))
  end
end

-- ========== 主循环 ==========

local function mainLoop()
  log.info("main", "进入主循环 mode=" .. app.mode)

  while app.running do
    local now = computer.uptime()

    -- 硬件重扫
    if app.needRescan or now >= app.nextHardwareRescan then
      doHardwareScan()
      app.needRescan = false
      app.nextHardwareRescan = now + config.hardwareRescan
    end

    if app.needImport then
      local n = model.importFromMaintainers(app.hw.levelMaintainers, config.importProfile)
      app.needImport = false
      if n > 0 then
        app.configDirty = true
        ui.setLastAction("imported " .. n .. " targets")
        ui.markDirty()
      end
    end

    -- 库存扫描
    if now >= app.nextInventoryScan then
      doInventoryScan()
      app.nextInventoryScan = now + config.scanInterval
    end

    -- 状态推导
    updateTargetStates()

    -- 调度
    if now >= app.nextSchedule then
      doSchedule()
      app.nextSchedule = now + config.scheduleTick
      ui.setNextSchedule(app.nextSchedule)
    end

    -- 控制器推进 (非阻塞)
    if app.mode == "control" then
      controller.tick(now, config, app.hw)
    end

    -- 配置保存
    saveConfig()

    -- 渲染
    local fresh = app.mode == "simulate" or inventory.isFresh(now, config.maxSnapshotAge)
    ui.render(app.hw, config, now, model.getTargets(), fresh)

    -- 事件等待
    local timeout = math.max(0.05, math.min(0.25,
      math.min(app.nextInventoryScan, app.nextSchedule) - now))
    local ev = table.pack(event.pull(timeout))

    if ev.n > 0 then
      if ev[1] == "interrupted" then
        app.running = false
        log.info("main", "收到 interrupted 信号，退出")
      else
        ui.dispatch(ev, app)
      end
    end
  end
end

-- ========== 清理 ==========

local function cleanup()
  log.info("main", "开始清理...")
  -- 停止所有受管机器
  if app.hw and app.mode == "control" then
    controller.stopAll("shutdown")
  end
  -- 保存配置（退出时忽略节流）
  saveConfig(true)
  -- 恢复终端
  ui.restore()
  -- 关闭日志
  log.close()
end

local function showCrashAndWait(err)
  local message = "SEUI crash:\n" .. tostring(err)
  local path = config.crashFile or "/home/seui-crash.log"
  local f = io.open(path, "w")
  if f then
    f:write(message, "\n")
    f:close()
  end
  io.stderr:write(message .. "\n\n")
  io.stderr:write("Crash report: " .. path .. "\n")
  io.stderr:write("Press any key or touch the screen to exit.\n")
  -- 不再让错误只闪几帧：用户确认前保持在恢复后的终端上。
  while true do
    local ok, name = pcall(event.pull)
    if not ok or name == "key_down" or name == "touch" or name == "interrupted" then
      break
    end
  end
end

-- ========== 入口 ==========

local function run()
  initLog()
  initStore()

  -- 加载配置
  loadOrCreateConfig()

  -- 模拟模式注入假数据
  if app.mode == "simulate" then
    model.clear()
    injectSimulatedData()
  end

  -- 初始化 UI
  initUI()

  -- 硬件扫描
  if app.mode ~= "simulate" then
    doHardwareScan()
  else
    -- 模拟模式下创建空硬件快照
    app.hw = { pumps = {}, miners = {}, levelMaintainers = {}, transposers = {},
               fluidInterface = nil, meInterface = nil, database = nil,
               gpu = component.gpu, screen = component.screen, paramBackend = "keyed" }
  end

  -- 首次库存扫描
  if app.mode ~= "simulate" then
    doInventoryScan()
  end

  app.nextInventoryScan = computer.uptime() + config.scanInterval
  app.nextSchedule = computer.uptime() + config.scheduleTick
  app.nextHardwareRescan = computer.uptime() + config.hardwareRescan

  -- 主循环 (带崩溃保护)
  local ok, err = xpcall(mainLoop, debug.traceback)
  if not ok then
    log.fatal("main", "崩溃: " .. tostring(err))
    local cleanupOK, cleanupErr = pcall(cleanup)
    if not cleanupOK then
      err = tostring(err) .. "\ncleanup failed: " .. tostring(cleanupErr)
    end
    showCrashAndWait(err)
    return
  end

  cleanup()
end

run()
