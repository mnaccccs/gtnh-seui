-- SEUI config.lua
-- 用户可编辑的运行参数

local sides = require("sides")

local config = {
  -- ========== 屏幕 ==========
  screenWidth = 160,
  screenHeight = 50,
  colorDepth = 8,

  -- ========== 扫描周期 (秒) ==========
  scanInterval = 60,       -- ME 库存扫描（与 Wiki 原程序一致）
  hardwareRescan = 60,    -- 硬件组件重扫兜底
  targetRescan = 30,      -- level_maintainer 重扫
  scheduleTick = 1,       -- 调度器推进
  maxSnapshotAge = 75,    -- 快照过期阈值，需大于 scanInterval

  -- ========== 安全 ==========
  failClosed = true,      -- 传感器断开时是否停机
  idleTimeout = 30,       -- WAIT_IDLE 硬超时 (秒)
  switchCooldown = 10,    -- 两次换配方最短间隔
  stopAllConfirmTime = 3,-- STOP ALL 二次确认窗口

  -- ========== 调度默认值 ==========
  lowRatio = 0.90,
  highRatio = 1.00,
  minDwell = 30,
  maxBatch = 30,

  -- ========== UI ==========
  rowsPerCol = 14,
  colWidth = 51,
  -- 颜色
  color = {
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
  },

  -- ========== 数据文件 ==========
  dataFile = "/etc/seui.dat",
  logFile  = "/var/log/seui.log",
  crashFile = "/home/seui-crash.log",
  logMaxSize = 65536,
  logKeep = 3,

  -- ========== 权限 ==========
  authorizedUsers = nil,  -- nil 表示不额外限制；设为 {"PlayerName"} 时只允许列内玩家操作

  -- ========== 无人机后端 ==========
  droneBackend = "transposer", -- "transposer" / "me_interface" / "manual"
  -- Wiki 全体同步布局：所有转运器摆向一致，并连接同频道共享末影箱。
  droneSide = sides.down, -- 所有转运器朝共享无人机末影箱的一侧
  inputSide = sides.up,   -- 所有转运器朝矿机输入总线的一侧
  allowRandomDrone = false,  -- 缺无人机时是否随机选替代
  -- me_interface 后端：每个无人机等级对应 database 中两种供应物的 1 基槽位
  -- 示例：droneDatabaseSlots = { [8] = {15, 16} }
  droneDatabaseSlots = {},

  -- ========== 旧 batch 解码 profile ==========
  importProfile = "v1_simple", -- "v1_simple" 或 "v2.2_extended"

  -- ========== 初始目标 (空表示从 level_maintainer 导入) ==========
  targets = {},

  -- ========== 兼容模式 ==========
  compatAllPumpsOneTarget = true,  -- 第一版：所有泵追同一目标
  compatAllMinersOneTarget = true,
}

return config
