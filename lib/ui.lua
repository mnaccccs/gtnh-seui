-- SEUI lib/ui.lua
-- 160x50 触摸 UI：三页 PUMP/MINER/SYSTEM + 三列目标矩阵 + 底部操作区

local component = require("component")
local unicode = require("unicode")
local computer = require("computer")
local term = require("term")
local format = require("lib.format")
local log = require("lib.log")
local model = require("lib.model")
local controller = require("lib.controller")
local inventory = require("lib.inventory")

local M = {}

-- ========== 布局常量 ==========
local W = 160
local H = 50
local COL_X = {2, 54, 106}
local COL_W = 51
local ROWS_PER_COL = 14
local BAR_W = 47

-- ========== 状态 ==========
local ui = {
  gpu = nil,
  screen = nil,
  page = "pump",      -- pump / miner / system
  selectedId = nil,
  pageOffset = 0,     -- 分页偏移
  modal = nil,        -- 模态编辑框
  hitboxGroups = { header = {}, targets = {}, actions = {} },
  activeHitboxGroup = "actions",
  dirty = { all = true, header = true, targets = true, details = true, actions = true, system = true },
  lastAction = "idle",
  nextSchedule = 0,
  scanning = false,
  stopAllConfirm = 0, -- STOP ALL 确认时间戳
  savedFg = 0xffffff,
  savedBg = 0x000000,
  savedResolution = nil,
}

local STATE_ZH = {UNKNOWN="未知",OK="正常",LOW="不足",RUN="运行",WAIT="等待",OFF="关闭",FAULT="故障",STALE="过期",READY="就绪"}
local MODE_ZH = {OFF="关闭",TARGET="按目标",ALWAYS="持续"}
local PHASE_ZH = {IDLE="空闲",REQUEST_STOP="请求停机",WAIT_IDLE="等待停稳",PREPARE="准备",APPLY="写入参数",VERIFY="校验参数",START="启动",RUNNING="运行",REQUEST_END="结束任务",FAULT="故障"}

-- ========== 颜色 ==========
local C = {
  bg       = 0x1a1a2e,
  fg       = 0xc0c0c0,
  header   = 0x00bfff,
  ok       = 0x00ff00,
  low      = 0xff4444,
  run      = 0x00ffff,
  wait     = 0xffff00,
  off      = 0x556677,
  fault    = 0xff8800,
  stale    = 0xcc00ff,
  bar_bg   = 0x333344,
  bar_fill = 0x00aa00,
  bar_full = 0x00ff00,
  bar_low  = 0xff4444,
  selected = 0x224466,
  button   = 0x2a2a4a,
  button_on= 0x3a5a8a,
  modal_bg = 0x0a0a1a,
  dim      = 0x666688,
}

-- ========== 初始化 ==========
function M.init(gpu, screen, config)
  ui.gpu = gpu
  ui.screen = screen
  C = config and config.color or C

  -- 保存原始终端状态
  ui.savedFg, _ = gpu.getForeground()
  ui.savedBg, _ = gpu.getBackground()
  ui.savedResolution = { gpu.getResolution() }

  -- 绑定屏幕
  if screen then
    gpu.bind(screen.address or component.screen.address)
    if screen.setTouchModeInverted then
      screen.setTouchModeInverted(true)
    end
    if screen.setPrecise then
      screen.setPrecise(false)
    end
  end

  gpu.setResolution(W, H)
  gpu.setDepth(8)
  gpu.setBackground(C.bg)
  gpu.setForeground(C.fg)
  gpu.fill(1, 1, W, H, " ")

  ui.dirty.all = true
  log.info("ui", "UI 初始化完成 " .. W .. "x" .. H .. "x8")
end

function M.restore()
  if not ui.gpu then return end
  local gpu = ui.gpu
  gpu.setBackground(ui.savedBg)
  gpu.setForeground(ui.savedFg)
  if ui.savedResolution then
    gpu.setResolution(ui.savedResolution[1], ui.savedResolution[2])
  end
  if ui.screen and ui.screen.setTouchModeInverted then
    ui.screen.setTouchModeInverted(false)
  end
  term.clear()
  log.info("ui", "终端已恢复")
end

-- ========== 绘制原语 ==========
local function setColors(fg, bg)
  ui.gpu.setForeground(fg or C.fg)
  ui.gpu.setBackground(bg or C.bg)
end

local function drawText(x, y, text, fg, bg)
  setColors(fg, bg)
  ui.gpu.set(x, y, text)
end

local function fillRect(x, y, w, h, char, fg, bg)
  setColors(fg, bg)
  ui.gpu.fill(x, y, w, h, char or " ")
end

local function drawButton(x, y, w, text, enabled, action, payload)
  local h = 1
  local label = format.fitCenter(text, w)
  local bg = enabled and C.button or C.off
  local fg = enabled and C.fg or C.dim
  fillRect(x, y, w, h, " ", fg, bg)
  drawText(x, y, label, fg, bg)
  if action then
    local group = ui.hitboxGroups[ui.activeHitboxGroup] or ui.hitboxGroups.actions
    group[#group + 1] = {
      x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1,
      page = ui.page, enabled = enabled,
      action = action, payload = payload,
    }
  end
end

-- 注册命中区域
local function addHitbox(x, y, w, h, action, payload)
  local group = ui.hitboxGroups[ui.activeHitboxGroup] or ui.hitboxGroups.actions
  group[#group + 1] = {
    x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1,
    page = ui.page, enabled = true,
    action = action, payload = payload,
  }
end

-- ========== 状态颜色 ==========
local function stateColor(state)
  if state == "OK" then return C.ok
  elseif state == "LOW" then return C.low
  elseif state == "RUN" then return C.run
  elseif state == "WAIT" then return C.wait
  elseif state == "OFF" then return C.off
  elseif state == "FAULT" then return C.fault
  elseif state == "STALE" then return C.stale
  elseif state == "READY" then return C.dim
  else return C.fg
  end
end

-- ========== 绘制各区域 ==========

function M.renderHeader(hw, config, now)
  if not ui.dirty.header and not ui.dirty.all then return end
  ui.activeHitboxGroup = "header"
  ui.hitboxGroups.header = {}

  -- y=1: 标题 + 页签
  local title = "太空电梯智能控制台 v1.0.5"
  fillRect(1, 1, W, 1, " ", C.header, C.bg)
  drawText(2, 1, title, C.header, C.bg)
  local tabX = W - 24
  drawButton(tabX,      1, 6, "钻机", true, "tab_pump")
  drawButton(tabX + 7,  1, 7, "矿机", true, "tab_miner")
  drawButton(tabX + 15, 1, 8, "系统", true, "tab_system")
  local activeX, activeW, activeLabel
  if ui.page == "pump" then activeX, activeW, activeLabel = tabX, 6, "钻机"
  elseif ui.page == "miner" then activeX, activeW, activeLabel = tabX + 7, 7, "矿机"
  else activeX, activeW, activeLabel = tabX + 15, 8, "系统" end
  fillRect(activeX, 1, activeW, 1, " ", C.header, C.button_on)
  drawText(activeX, 1, format.fitCenter(activeLabel, activeW), C.header, C.button_on)

  -- y=2: 设备数 + 调度倒计时 + ME 耗时
  local snapshot = inventory.getSnapshot()
  local meTime = string.format("ME:%.2fs", snapshot.duration or 0)
  local nextS = math.max(0, math.floor((ui.nextSchedule or 0) - now))
  local pumpCount = #hw.pumps
  local minerCount = #hw.miners
  local runtimeMode = ({simulate="模拟",readonly="只读",control="控制"})[config.runtimeMode] or tostring(config.runtimeMode or "?")
  local info = string.format("模式:%s 钻机:%d 矿机:%d 扫描:%ds %s 下次:%ds 内存:%dKB",
    runtimeMode, pumpCount, minerCount, config.scanInterval, meTime, nextS,
    math.floor(computer.freeMemory() / 1024))
  fillRect(1, 2, W, 1, " ", C.dim, C.bg)
  drawText(2, 2, info, C.dim, C.bg)

  -- y=3: 最近动作 + Refresh
  fillRect(1, 3, W, 1, " ", C.fg, C.bg)
  drawText(2, 3, "操作: " .. (ui.lastAction or "空闲"), C.fg, C.bg)

  local refreshLabel = ui.scanning and "[扫描中]" or "[刷新]"
  local refreshX = W - 30
  drawButton(refreshX - 10, 3, 9, "导入", true, "import_targets")
  drawButton(refreshX, 3, 12, refreshLabel, not ui.scanning, "refresh")
  drawButton(refreshX + 12, 3, 9, "[重扫]", true, "rescan")
  drawButton(refreshX + 22, 3, 8, "[停机]", true, "stop_all")

  -- y=4: 分隔
  fillRect(1, 4, W, 1, "-", C.dim, C.bg)

  ui.dirty.header = false
end

function M.renderTargets(targets, snapshotFresh, now, config)
  if not ui.dirty.targets and not ui.dirty.all then return end
  ui.activeHitboxGroup = "targets"
  ui.hitboxGroups.targets = {}

  local pageTargets = {}
  local maxItems = ROWS_PER_COL * 3  -- 42

  -- 过滤当前 domain
  for _, t in ipairs(targets) do
    if t.domain == ui.page or ui.page == "system" then
      table.insert(pageTargets, t)
    end
  end

  -- 分页
  local total = #pageTargets
  local startIdx = ui.pageOffset * maxItems + 1
  local endIdx = math.min(startIdx + maxItems - 1, total)

  -- 清空目标区域
  fillRect(1, 5, W, 28, " ", C.fg, C.bg)

  -- 绘制每个目标
  for i = startIdx, endIdx do
    local t = pageTargets[i]
    if not t then break end

    local idx = i - startIdx + 1
    local x, y = format.intDiv(idx - 1, ROWS_PER_COL), (idx - 1) % ROWS_PER_COL
    x = COL_X[x + 1] or COL_X[1]
    y = 5 + y * 2

    -- 第一行：序号 标签 模式 数量 权重 状态
    local isSelected = (ui.selectedId == t.id)
    local state = t.runtime.state or "UNKNOWN"
    local sc = stateColor(state)
    local modeChar = t.mode == "TARGET" and "T" or (t.mode == "ALWAYS" and "A" or "O")
    local amtStr = format.formatAmount(t.current) .. "/" .. format.formatAmount(t.target)
    local wStr = string.format("w%+d", t.weight or 0)

    local line1 = string.format("%02d %s %s %s %s",
      idx, format.fit(t.label, 18), modeChar, format.fit(amtStr, 22), wStr)
    line1 = format.fit(line1, COL_W - 8) .. string.format(" %-6s", STATE_ZH[state] or state)

    local bg = isSelected and C.selected or C.bg
    local fg = sc
    fillRect(x, y, COL_W, 1, " ", fg, bg)
    drawText(x, y, line1, fg, bg)

    -- 点击选中
    addHitbox(x, y, COL_W, 1, "select", { id = t.id })

    -- 第二行：进度条
    local ratio = 0
    if t.target > 0 then
      ratio = math.min(1, math.max(0, (t.current + t.pending) / t.target))
    end
    local filled = math.floor(ratio * BAR_W + 0.5)
    local barColor = ratio >= 0.9 and C.bar_full or (ratio >= 0.5 and C.bar_fill or C.bar_low)

    fillRect(x, y + 1, BAR_W, 1, " ", C.fg, C.bar_bg)
    if filled > 0 then
      fillRect(x, y + 1, filled, 1, " ", C.fg, barColor)
    end

    -- 百分比文字叠加
    local pctStr = string.format("%3d%%", math.floor(ratio * 100))
    drawText(x + BAR_W - 4, y + 1, pctStr, C.fg, barColor)
  end

  -- y=33: 分页信息
  local pages = math.max(1, math.ceil(total / maxItems))
  local pageStr = string.format("第 %d/%d 页  共 %d 项（滚轮或上/下页）",
    ui.pageOffset + 1, pages, total)
  fillRect(1, 33, W, 1, " ", C.dim, C.bg)
  drawText(2, 33, pageStr, C.dim, C.bg)

  -- Prev/Next 按钮
  if pages > 1 then
    drawButton(W - 22, 33, 7, "[上页]", ui.pageOffset > 0, "prev_page")
    drawButton(W - 14, 33, 7, "[下页]", ui.pageOffset < pages - 1, "next_page")
  end

  ui.dirty.targets = false
end

function M.renderDetails(targets, now)
  if not ui.dirty.details and not ui.dirty.all then return end

  fillRect(1, 34, W, 3, " ", C.fg, C.bg)

  local t = ui.selectedId and model.getById(ui.selectedId) or nil
  if not t then
    drawText(2, 35, "(未选择目标 — 点击列表中的目标查看详情)", C.dim, C.bg)
    ui.dirty.details = false
    return
  end

  local state = t.runtime.state or "UNKNOWN"
  local sc = stateColor(state)
  local ratio = model.getRatio(t)

  -- y=34: 标题行
  drawText(2, 34, format.fit(t.label, 30), C.header, C.bg)
  drawText(33, 34, string.format("标识:%s  模式:%s  权重:%+d  %s",
    t.id, MODE_ZH[t.mode] or t.mode, t.weight or 0, STATE_ZH[state] or state), sc, C.bg)

  -- y=35: 数量详情
  drawText(2, 35, string.format("当前:%s  目标:%s  待处理:%s  比例:%.1f%%",
    format.formatAmount(t.current), format.formatAmount(t.target),
    format.formatAmount(t.pending), ratio * 100), C.fg, C.bg)

  -- y=36: 路由参数
  if t.domain == "pump" then
    drawText(2, 36, string.format("星球类型:%s  气体类型:%s  批处理:%s  基础流量:%s L/s",
      tostring(t.route.planetType or "?"),
      tostring(t.route.gasType or "?"),
      tostring(t.route.maxBatch or "?"), format.formatAmount(t.route.baseRate or 0)), C.dim, C.bg)
  else
    drawText(2, 36, string.format("drone:%s  dist:%s  parallel:%s",
      tostring(t.route.droneTier or "?"),
      tostring(t.route.distance or "?"),
      tostring(t.route.parallel or "auto")), C.dim, C.bg)
  end

  ui.dirty.details = false
end

function M.renderActions(config)
  if not ui.dirty.actions and not ui.dirty.all then return end
  ui.activeHitboxGroup = "actions"
  ui.hitboxGroups.actions = {}

  fillRect(1, 37, W, 14, " ", C.fg, C.bg)

  if ui.page == "system" then
    M.renderSystemPage(config)
    ui.dirty.actions = false
    return
  end

  -- ===== 操作按钮 =====
  local y = 37

  drawText(2, y, "优先级", C.dim, C.bg)
  drawButton(12, y, 5, "[顶]", true, "priority", { dir = "top" })
  drawButton(18, y, 5, "[上]",  true, "priority", { dir = "up" })
  drawButton(24, y, 7, "[下移]", true, "priority", { dir = "down" })
  drawButton(32, y, 8, "[底部]", true, "priority", { dir = "bottom" })

  -- MODE
  y = y + 2
  drawText(2, y, "模式", C.dim, C.bg)
  drawButton(12, y, 6, "[关闭]", true, "mode", { mode = "OFF" })
  drawButton(19, y, 9, "[按目标]", true, "mode", { mode = "TARGET" })
  drawButton(29, y, 8, "[持续]", true, "mode", { mode = "ALWAYS" })

  -- VALUE
  drawText(40, y, "目标量", C.dim, C.bg)
  drawButton(47, y, 7, "[当前]", true, "set_current")
  drawButton(55, y, 7, "[输入]", true, "edit_value")

  -- WEIGHT
  drawText(65, y, "权重", C.dim, C.bg)
  drawButton(73, y, 5, "[-10]", true, "weight", { delta = -10 })
  drawButton(79, y, 5, "[-5]",  true, "weight", { delta = -5 })
  drawButton(85, y, 5, "[-1]",  true, "weight", { delta = -1 })
  drawButton(91, y, 5, "[+1]",  true, "weight", { delta = 1 })
  drawButton(97, y, 5, "[+5]",  true, "weight", { delta = 5 })
  drawButton(103, y, 6, "[+10]", true, "weight", { delta = 10 })

  local selected = ui.selectedId and model.getById(ui.selectedId) or nil
  if selected and selected.domain == "pump" then
    drawButton(112, y, 10, "[星球]", true, "edit_route", { field = "planetType" })
    drawButton(123, y, 8, "[气体]", true, "edit_route", { field = "gasType" })
  elseif selected and selected.domain == "miner" then
    drawButton(112, y, 10, "[DRONE]", true, "edit_route", { field = "droneTier" })
    drawButton(123, y, 10, "[DIST]", true, "edit_route", { field = "distance" })
  end

  -- 目标值快速设置
  y = y + 2
  local presets = {
    { label = "=10M",  val = 1e7 },
    { label = "=50M",  val = 5e7 },
    { label = "=100M", val = 1e8 },
    { label = "=500M", val = 5e8 },
    { label = "=1G",   val = 1e9 },
    { label = "=5G",   val = 5e9 },
    { label = "=10G",  val = 1e10 },
    { label = "=50G",  val = 5e10 },
    { label = "=100G", val = 1e11 },
    { label = "=500G", val = 5e11 },
    { label = "=1T",   val = 1e12 },
    { label = "=500T", val = 5e14 },
  }
  for i, p in ipairs(presets) do
    local x = 2 + (i - 1) * 13
    if x + 12 > W then break end
    drawButton(x, y, 11, "[" .. p.label .. "]", true, "set_target", { val = p.val })
  end

  -- 增加
  y = y + 1
  local adds = {
    { label = "+10M",  val = 1e7 },  { label = "+50M",  val = 5e7 },
    { label = "+100M", val = 1e8 },  { label = "+500M", val = 5e8 },
    { label = "+1G",   val = 1e9 },  { label = "+5G",   val = 5e9 },
    { label = "+10G",  val = 1e10 }, { label = "+50G",  val = 5e10 },
    { label = "+100G", val = 1e11 }, { label = "+500G", val = 5e11 },
    { label = "+1T",   val = 1e12 }, { label = "+500T", val = 5e14 },
  }
  for i, p in ipairs(adds) do
    local x = 2 + (i - 1) * 13
    if x + 12 > W then break end
    drawButton(x, y, 11, "[" .. p.label .. "]", true, "add_target", { val = p.val })
  end

  -- 减少
  y = y + 1
  local subs = {
    { label = "-10M",  val = 1e7 },  { label = "-50M",  val = 5e7 },
    { label = "-100M", val = 1e8 },  { label = "-500M", val = 5e8 },
    { label = "-1G",   val = 1e9 },  { label = "-5G",   val = 5e9 },
    { label = "-10G",  val = 1e10 }, { label = "-50G",  val = 5e10 },
    { label = "-100G", val = 1e11 }, { label = "-500G", val = 5e11 },
    { label = "-1T",   val = 1e12 }, { label = "-500T", val = 5e14 },
  }
  for i, p in ipairs(subs) do
    local x = 2 + (i - 1) * 13
    if x + 12 > W then break end
    drawButton(x, y, 11, "[" .. p.label .. "]", true, "sub_target", { val = p.val })
  end

  -- STOP ALL 确认
  if ui.stopAllConfirm > 0 and computer.uptime() < ui.stopAllConfirm then
    drawButton(W - 20, y - 3, 18, "[CONFIRM STOP?]", true, "stop_all_confirm")
  end

  ui.dirty.actions = false
end

function M.renderSystemPage(config)
  local hw = require("lib.discovery").getHardware()
  local snap = inventory.getSnapshot()
  local ws = controller.status()

  local y = 37

  -- 组件健康
  drawText(2, y, "=== 组件健康 ===", C.header, C.bg)
  y = y + 1

  local lines = {
    string.format("GPU:        %s  Screen: %s", tostring(ui.gpu ~= nil), tostring(ui.screen ~= nil)),
    string.format("fluid_if:   %s  me_if:  %s",
      tostring(hw.fluidInterface ~= nil), tostring(hw.meInterface ~= nil)),
    string.format("pumps: %d  miners: %d  maintainers: %d  transposers: %d",
      #hw.pumps, #hw.miners, #hw.levelMaintainers, #hw.transposers),
    string.format("param backend: %s", hw.paramBackend or "unknown"),
    string.format("snapshot: %s  age: %.1fs  duration: %.3fs",
      snap.error and "ERROR" or "OK",
      computer.uptime() - (snap.timestamp or 0),
      snap.duration or 0),
  }

  if snap.error then
    table.insert(lines, "snapshot error: " .. snap.error)
  end

  for _, line in ipairs(lines) do
    drawText(2, y, format.fit(line, 78), C.fg, C.bg)
    y = y + 1
  end

  -- 机器状态 (右侧)
  local my = 37
  drawText(80, my, "=== 机器状态 ===", C.header, C.bg)
  my = my + 1

  local count = 0
  for addr, w in pairs(ws) do
    if count < 5 then
      local short = addr:sub(1, 8)
      local line = string.format("%s  %-12s  %s",
        short, w.phase, w.servingTarget and w.servingTarget:sub(1, 20) or "-")
      drawText(80, my, format.fit(line, 78), stateColor(w.phase == "FAULT" and "FAULT" or "RUN"), C.bg)
      if w.phase == "FAULT" then
        addHitbox(80, my, 78, 1, "retry_worker", { address = addr })
      end
      if w.lastError then
        my = my + 1
        drawText(80, my, "  err: " .. format.fit(w.lastError, 72), C.fault, C.bg)
      end
      my = my + 1
      count = count + 1
    end
  end

  -- 日志 (底部)
  y = math.max(y, my) + 1
  if y <= H then
    drawText(2, y, "=== 最近日志 ===", C.header, C.bg)
    y = y + 1
  end

  local entries = log.getRecent(8)
  for _, entry in ipairs(entries) do
    if y <= H then
      drawText(2, y, format.fit(entry, W - 2), C.dim, C.bg)
      y = y + 1
    end
  end
end

-- ========== 模态编辑框 ==========
function M.openNumberModal(title, initialText, onSubmit)
  ui.modal = {
    kind = "number",
    title = title,
    text = tostring(initialText or ""),
    cursor = #(tostring(initialText or "")) + 1,
    onSubmit = onSubmit,
    error = nil,
  }
  ui.dirty.all = true
end

function M.renderModal()
  if not ui.modal then return end

  -- 模态框: 居中 40x6
  local mw, mh = 50, 7
  local mx = math.floor((W - mw) / 2) + 1
  local my = math.floor((H - mh) / 2) + 1

  -- 背景
  fillRect(mx, my, mw, mh, " ", C.fg, C.modal_bg)

  -- 边框
  drawText(mx, my, "+" .. string.rep("-", mw - 2) .. "+", C.header, C.modal_bg)
  drawText(mx, my + mh - 1, "+" .. string.rep("-", mw - 2) .. "+", C.header, C.modal_bg)
  for y = my + 1, my + mh - 2 do
    drawText(mx, y, "|", C.header, C.modal_bg)
    drawText(mx + mw - 1, y, "|", C.header, C.modal_bg)
  end

  -- 标题
  drawText(mx + 2, my + 1, format.fit(ui.modal.title, mw - 4), C.header, C.modal_bg)

  -- 输入框
  local inputY = my + 3
  fillRect(mx + 2, inputY, mw - 4, 1, " ", C.fg, C.bg)
  drawText(mx + 2, inputY, ui.modal.text, C.fg, C.bg)
  -- 光标位置用反色
  if ui.modal.cursor and ui.modal.cursor <= #ui.modal.text then
    local before = ui.modal.text:sub(1, ui.modal.cursor - 1)
    local char = ui.modal.text:sub(ui.modal.cursor, ui.modal.cursor)
    if char and #char > 0 then
      drawText(mx + 2 + #before, inputY, char, C.bg, C.fg)
    end
  end

  -- 错误
  if ui.modal.error then
    drawText(mx + 2, inputY + 1, format.fit(ui.modal.error, mw - 4), C.fault, C.modal_bg)
  end

  -- 提示
  drawText(mx + 2, my + mh - 2, "Enter=Submit  Esc=Cancel  Backspace=Del", C.dim, C.modal_bg)
end

function M.closeModal()
  ui.modal = nil
  ui.dirty.all = true
end

-- ========== 主渲染 ==========
function M.render(hw, config, now, targets, snapshotFresh)
  if ui.dirty.all then
    fillRect(1, 1, W, H, " ", C.fg, C.bg)
    ui.dirty.all = false
    ui.dirty.header = true
    ui.dirty.targets = true
    ui.dirty.details = true
    ui.dirty.actions = true
  end

  M.renderHeader(hw, config, now)
  M.renderTargets(targets, snapshotFresh, now, config)
  M.renderDetails(targets, now)
  M.renderActions(config)
  M.renderModal()
end

function M.markDirty()
  ui.dirty.all = true
  ui.dirty.header = true
  ui.dirty.targets = true
  ui.dirty.details = true
  ui.dirty.actions = true
end

-- ========== 事件分发 ==========
function M.dispatch(ev, app)
  local name = ev[1]
  if not name then return end

  if name == "touch" then
    if ui.screen and ui.screen.address and ev[2] ~= ui.screen.address then return end
    M.handleTouch(ev[3], ev[4], ev[5], ev[6], app)
  elseif name == "scroll" then
    if ui.screen and ui.screen.address and ev[2] ~= ui.screen.address then return end
    M.handleScroll(ev[3], ev[4], ev[5], app)
  elseif name == "key_down" then
    M.handleKeyDown(ev[3], ev[4], ev[6], app)
  elseif name == "clipboard" then
    M.handleClipboard(ev[3], app)
  elseif name == "component_added" or name == "component_removed"
      or name == "component_available" or name == "component_unavailable" then
    -- 硬件变更标记重扫
    app.needRescan = true
  end
end

function M.handleTouch(x, y, button, username, app)
  -- 模态框优先
  if ui.modal then
    -- 点击模态外区域 = 取消
    -- 这里简化：模态只能通过键盘操作
    return
  end

  -- 高层组优先：actions > targets > header。
  for _, groupName in ipairs({"actions", "targets", "header"}) do
    local group = ui.hitboxGroups[groupName] or {}
    for i = #group, 1, -1 do
      local hb = group[i]
      if hb.page == ui.page or hb.page == nil then
        if x >= hb.x1 and x <= hb.x2 and y >= hb.y1 and y <= hb.y2 then
          if not hb.enabled then return end
          M.handleAction(hb.action, hb.payload, button, username, app)
          return
        end
      end
    end
  end
end

function M.handleScroll(x, y, direction, app)
  if direction > 0 then
    -- 向上滚 = 上一页
    if ui.pageOffset > 0 then
      ui.pageOffset = ui.pageOffset - 1
      ui.dirty.targets = true
    end
  else
    -- 向下滚 = 下一页
    local targets = model.getByDomain(ui.page)
    local maxItems = ROWS_PER_COL * 3
    local pages = math.max(1, math.ceil(#targets / maxItems))
    if ui.pageOffset < pages - 1 then
      ui.pageOffset = ui.pageOffset + 1
      ui.dirty.targets = true
    end
  end
end

function M.handleKeyDown(char, code, username, app)
  local typed = ""
  if type(char) == "number" and char > 0 then
    local ok, value = pcall(unicode.char, char)
    if ok then typed = value end
  elseif type(char) == "string" then
    typed = char
  end
  if ui.modal then
    -- 模态输入
    if code == 28 then -- Enter
      local val, err = format.parseSize(ui.modal.text)
      if not val then
        ui.modal.error = err or "parse error"
        ui.dirty.all = true
        return
      end
      if ui.modal.onSubmit then
        ui.modal.onSubmit(val)
      end
      M.closeModal()
    elseif code == 1 then -- Esc
      M.closeModal()
    elseif code == 14 then -- Backspace
      if #ui.modal.text > 0 then
        ui.modal.text = ui.modal.text:sub(1, #ui.modal.text - 1)
        ui.modal.cursor = #ui.modal.text + 1
        ui.modal.error = nil
        ui.dirty.all = true
      end
    else
      -- 普通字符
      if typed ~= "" and string.byte(typed) and string.byte(typed) >= 32 then
        ui.modal.text = ui.modal.text .. typed
        ui.modal.cursor = #ui.modal.text + 1
        ui.modal.error = nil
        ui.dirty.all = true
      end
    end
    return
  end

  -- 已选目标时直接键入数字即可打开目标量输入框，不必先点“输入”。
  if ui.selectedId and typed:match("^[0-9%.]$") then
    M.openNumberModal("直接输入目标量（支持 M/G/T）", typed, function(val)
      local t = model.getById(ui.selectedId)
      if t then
        t.target = val
        if t.mode == "OFF" and val > 0 then t.mode = "TARGET" end
        app.configDirty = true
        ui.lastAction = "目标量=" .. format.formatAmount(val)
      end
    end)
    return
  end

  -- 非模态快捷键（无选中目标时 1/2/3 切换页面）
  if code == 2 then -- 1 键 = PUMP
    ui.page = "pump"
    ui.pageOffset = 0
    M.markDirty()
  elseif code == 3 then -- 2 键 = MINER
    ui.page = "miner"
    ui.pageOffset = 0
    M.markDirty()
  elseif code == 4 then -- 3 键 = SYSTEM
    ui.page = "system"
    M.markDirty()
  end
end

function M.handleClipboard(text, app)
  if ui.modal and text then
    ui.modal.text = ui.modal.text .. text
    ui.modal.cursor = #ui.modal.text + 1
    ui.modal.error = nil
    ui.dirty.all = true
  end
end

-- ========== 动作处理 ==========
function M.handleAction(action, payload, button, username, app)
  -- 权限检查
  if app.config.authorizedUsers then
    local authorized = false
    if username then
      for _, u in ipairs(app.config.authorizedUsers) do
        if u == username then authorized = true break end
      end
    end
    if not authorized then
      log.warn("ui", "未授权用户: " .. tostring(username))
      return
    end
  end

  if action == "tab_pump" then
    ui.page = "pump"
    ui.pageOffset = 0
    app.configDirty = true
    M.markDirty()

  elseif action == "tab_miner" then
    ui.page = "miner"
    ui.pageOffset = 0
    app.configDirty = true
    M.markDirty()

  elseif action == "tab_system" then
    ui.page = "system"
    app.configDirty = true
    M.markDirty()

  elseif action == "refresh" then
    app.nextInventoryScan = 0  -- 立即触发扫描
    ui.lastAction = "refresh requested"

  elseif action == "import_targets" then
    app.needImport = true
    ui.lastAction = "level maintainer import requested"

  elseif action == "rescan" then
    app.needRescan = true
    ui.lastAction = "rescan requested"

  elseif action == "stop_all" then
    -- 二次确认
    local now = computer.uptime()
    if ui.stopAllConfirm > 0 and now < ui.stopAllConfirm then
      controller.stopAll("user requested")
      ui.stopAllConfirm = 0
      ui.lastAction = "STOP ALL executed"
    else
      ui.stopAllConfirm = now + (app.config.stopAllConfirmTime or 3)
      ui.lastAction = "STOP ALL armed (click again to confirm)"
    end
    M.markDirty()

  elseif action == "stop_all_confirm" then
    controller.stopAll("user confirmed")
    ui.stopAllConfirm = 0
    ui.lastAction = "STOP ALL confirmed"
    M.markDirty()

  elseif action == "retry_worker" then
    if payload and payload.address and controller.retry(payload.address) then
      ui.lastAction = "retry " .. payload.address:sub(1, 8)
      M.markDirty()
    end

  elseif action == "select" then
    ui.selectedId = payload.id
    ui.dirty.details = true
    ui.dirty.targets = true
    app.configDirty = true

  elseif action == "priority" then
    if ui.selectedId then
      model.moveOrder(ui.selectedId, payload.dir)
      ui.dirty.targets = true
      ui.dirty.details = true
      ui.lastAction = "priority " .. payload.dir
      app.configDirty = true
    end

  elseif action == "mode" then
    if ui.selectedId then
      local t = model.getById(ui.selectedId)
      if t then
        t.mode = payload.mode
        ui.dirty.targets = true
        ui.dirty.details = true
        ui.lastAction = "mode=" .. payload.mode .. " for " .. t.id
        app.configDirty = true
      end
    end

  elseif action == "set_current" then
    if ui.selectedId then
      local t = model.getById(ui.selectedId)
      if t then
        t.target = t.current
        ui.dirty.targets = true
        ui.dirty.details = true
        ui.lastAction = "target set to current: " .. format.formatAmount(t.target)
        app.configDirty = true
      end
    end

  elseif action == "edit_value" then
    if ui.selectedId then
      local t = model.getById(ui.selectedId)
      if t then
        M.openNumberModal("目标值 (如 10M, 1.5G, 500T)", tostring(math.floor(t.target)),
          function(val)
            t.target = val
            ui.dirty.targets = true
            ui.dirty.details = true
            ui.lastAction = "target edited: " .. format.formatAmount(val)
            app.configDirty = true
          end)
      end
    end

  elseif action == "weight" then
    if ui.selectedId then
      local t = model.getById(ui.selectedId)
      if t then
        t.weight = (t.weight or 0) + payload.delta
        ui.dirty.details = true
        ui.dirty.targets = true
        ui.lastAction = "weight " .. (payload.delta >= 0 and "+" or "") .. payload.delta
        app.configDirty = true
      end
    end

  elseif action == "edit_route" then
    if ui.selectedId then
      local t = model.getById(ui.selectedId)
      if t and payload and payload.field then
        local field = payload.field
        M.openNumberModal("路由参数: " .. field, tostring(t.route[field] or 0), function(val)
          t.route[field] = math.floor(val)
          ui.dirty.targets = true
          ui.dirty.details = true
          ui.lastAction = field .. "=" .. tostring(math.floor(val))
          app.configDirty = true
        end)
      end
    end

  elseif action == "set_target" then
    if ui.selectedId then
      local t = model.getById(ui.selectedId)
      if t then
        t.target = payload.val
        ui.dirty.targets = true
        ui.dirty.details = true
        ui.lastAction = "target = " .. format.formatAmount(payload.val)
        app.configDirty = true
      end
    end

  elseif action == "add_target" then
    if ui.selectedId then
      local t = model.getById(ui.selectedId)
      if t then
        t.target = math.max(0, (t.target or 0) + payload.val)
        ui.dirty.targets = true
        ui.dirty.details = true
        ui.lastAction = "target += " .. format.formatAmount(payload.val)
        app.configDirty = true
      end
    end

  elseif action == "sub_target" then
    if ui.selectedId then
      local t = model.getById(ui.selectedId)
      if t then
        t.target = math.max(0, (t.target or 0) - payload.val)
        ui.dirty.targets = true
        ui.dirty.details = true
        ui.lastAction = "target -= " .. format.formatAmount(payload.val)
        app.configDirty = true
      end
    end

  elseif action == "prev_page" then
    if ui.pageOffset > 0 then
      ui.pageOffset = ui.pageOffset - 1
      ui.dirty.targets = true
    end

  elseif action == "next_page" then
    local targets = model.getByDomain(ui.page)
    local maxItems = ROWS_PER_COL * 3
    local pages = math.max(1, math.ceil(#targets / maxItems))
    if ui.pageOffset < pages - 1 then
      ui.pageOffset = ui.pageOffset + 1
      ui.dirty.targets = true
    end
  end
end

function M.setNextSchedule(t)
  ui.nextSchedule = t
  ui.dirty.header = true
end

function M.setScanning(s)
  ui.scanning = s
  ui.dirty.header = true
end

function M.setLastAction(s)
  ui.lastAction = s
  ui.dirty.header = true
end

function M.getState()
  return {
    page = ui.page,
    selectedId = ui.selectedId,
    pageOffset = ui.pageOffset,
  }
end

function M.setState(state)
  state = state or {}
  if state.page == "pump" or state.page == "miner" or state.page == "system" then
    ui.page = state.page
  end
  ui.selectedId = state.selectedId
  ui.pageOffset = tonumber(state.pageOffset) or 0
  M.markDirty()
end

return M
