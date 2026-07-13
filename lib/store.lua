-- SEUI lib/store.lua
-- 配置持久化 (原子保存 + bak 恢复)

local fs = require("filesystem")
local serialization = require("serialization")
local log = require("lib.log")

local M = {}

local DATA_FILE = "/etc/seui.dat"

-- OpenOS 1.12.44 的反序列化函数名是 unserialize；host mock/部分兼容库可能叫 deserialize。
local function decode(content)
  local fn = serialization.unserialize or serialization.deserialize
  if type(fn) ~= "function" then return nil, "unserialize unavailable" end
  local ok, value, reason = pcall(fn, content)
  if not ok then return nil, value end
  if value == nil then return nil, reason or "unserialize returned nil" end
  return value
end

function M.init(path)
  DATA_FILE = path or DATA_FILE
  local dir = fs.path(DATA_FILE)
  if dir and not fs.exists(dir) then
    fs.makeDirectory(dir)
  end
end

local function readAll(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function safeRename(from, to)
  local ok, result, reason = pcall(fs.rename, from, to)
  if not ok then return false, result end
  if result == false or result == nil then return false, reason or "rename failed" end
  return true
end

function M.load()
  local content = readAll(DATA_FILE)
  if not content or content == "" then
    -- 尝试 bak
    content = readAll(DATA_FILE .. ".bak")
    if not content or content == "" then
      return nil, "no config file"
    end
    log.warn("store", "主配置缺失，从 bak 恢复")
  end
  local data, decodeErr = decode(content)
  if type(data) ~= "table" then
    -- 尝试 bak
    content = readAll(DATA_FILE .. ".bak")
    if content and content ~= "" then
      data = decode(content)
      if type(data) == "table" then
        log.warn("store", "主配置损坏，从 bak 恢复")
        return data
      end
    end
    return nil, "config parse error: " .. tostring(decodeErr)
  end
  return data
end

function M.saveAtomic(config)
  -- 序列化并验证
  local ok, serialized = pcall(serialization.serialize, config)
  if not ok then
    return false, "serialize error: " .. tostring(serialized)
  end
  -- 反序列化验证
  local verified, verifyErr = decode(serialized)
  if type(verified) ~= "table" then
    return false, "roundtrip verify failed: " .. tostring(verifyErr)
  end

  local tmpFile = DATA_FILE .. ".tmp"
  local bakFile = DATA_FILE .. ".bak"

  -- 写 tmp
  local f = io.open(tmpFile, "w")
  if not f then return false, "cannot open tmp" end
  f:write(serialized)
  f:close()

  -- 确认写成功
  local check = readAll(tmpFile)
  if check ~= serialized then
    fs.remove(tmpFile)
    return false, "tmp write mismatch"
  end

  -- 旋转: 旧 bak 删除, dat -> bak, tmp -> dat
  if fs.exists(bakFile) then fs.remove(bakFile) end
  if fs.exists(DATA_FILE) then
    local ok3, err = safeRename(DATA_FILE, bakFile)
    if not ok3 then
      fs.remove(tmpFile)
      return false, "rename dat->bak failed: " .. tostring(err)
    end
  end
  local ok4, err4 = safeRename(tmpFile, DATA_FILE)
  if not ok4 then
    -- 尝试恢复 bak
    if fs.exists(bakFile) then safeRename(bakFile, DATA_FILE) end
    return false, "rename tmp->dat failed: " .. tostring(err4)
  end

  log.info("store", "配置已保存 (" .. #serialized .. " bytes)")
  return true
end

function M.migrate(config)
  if not config.schemaVersion or config.schemaVersion < 1 then
    config.schemaVersion = 1
  end
  if not config.ui then config.ui = { page = "pump", selectedId = nil } end
  if not config.scheduler then config.scheduler = {} end
  if not config.targets then config.targets = {} end
  return config
end

return M
