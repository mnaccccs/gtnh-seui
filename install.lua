-- GTNH SEUI OpenOS installer/updater
-- Requires an OpenComputers Internet Card and outbound access to raw.githubusercontent.com.

local component = require("component")
local fs = require("filesystem")
local shell = require("shell")

local args = shell.parse(...)
local target = args[1] or "/home/seui"
local base = "https://raw.githubusercontent.com/mnaccccs/gtnh-seui/main/"
local files = {
  "main.lua",
  "config.lua",
  "probe_bindings.lua",
  "lib/controller.lua",
  "lib/discovery.lua",
  "lib/drone.lua",
  "lib/fluid_catalog.lua",
  "lib/format.lua",
  "lib/inventory.lua",
  "lib/log.lua",
  "lib/model.lua",
  "lib/scheduler.lua",
  "lib/store.lua",
  "lib/ui.lua",
}

local internet = component.isAvailable("internet") and component.internet or nil
if not internet or type(internet.request) ~= "function" then
  io.stderr:write("安装失败：未检测到可用的 OC 互联网卡。\n")
  os.exit(1)
end

local function dirname(path)
  return path:match("^(.*)/[^/]+$")
end

local function download(url)
  local ok, request = pcall(internet.request, url)
  if not ok or not request then return nil, tostring(request) end
  local chunks = {}
  while true do
    local okRead, chunk = pcall(request)
    if not okRead then return nil, tostring(chunk) end
    if chunk == nil then break end
    chunks[#chunks + 1] = chunk
  end
  local data = table.concat(chunks)
  if data == "" then return nil, "empty response" end
  return data
end

local function writeAtomic(path, data)
  local dir = dirname(path)
  if dir and not fs.exists(dir) then
    local ok, reason = fs.makeDirectory(dir)
    if ok == false or ok == nil then return false, reason or "mkdir failed" end
  end
  local tmp = path .. ".tmp"
  local handle, reason = io.open(tmp, "wb")
  if not handle then return false, reason end
  handle:write(data)
  handle:close()
  if fs.exists(path) then fs.remove(path) end
  local ok, renameReason = fs.rename(tmp, path)
  if ok == false or ok == nil then
    fs.remove(tmp)
    return false, renameReason or "rename failed"
  end
  return true
end

if not fs.exists(target) then
  local ok, reason = fs.makeDirectory(target)
  if ok == false or ok == nil then
    io.stderr:write("无法创建目录：" .. tostring(reason) .. "\n")
    os.exit(1)
  end
end

local configPath = target .. "/config.lua"
local preserveConfig = fs.exists(configPath)
if preserveConfig then
  local source = io.open(configPath, "rb")
  if source then
    local old = source:read("*a")
    source:close()
    local backup = io.open(configPath .. ".bak", "wb")
    if backup then backup:write(old) backup:close() end
  end
end

for index, relative in ipairs(files) do
  if relative == "config.lua" and preserveConfig then
    print(string.format("[%d/%d] %s ... 保留现有配置（备份为 config.lua.bak）", index, #files, relative))
  else
    io.write(string.format("[%d/%d] %s ... ", index, #files, relative))
    local data, reason = download(base .. relative)
    if not data then
      io.stderr:write("失败\n下载失败：" .. tostring(reason) .. "\n")
      os.exit(1)
    end
    local ok, writeReason = writeAtomic(target .. "/" .. relative, data)
    if not ok then
      io.stderr:write("失败\n写入失败：" .. tostring(writeReason) .. "\n")
      os.exit(1)
    end
    print("完成")
  end
end

print("\nSEUI 已安装到 " .. target)
print("只读检查：" .. target .. "/main.lua --readonly")
print("实际控制：" .. target .. "/main.lua --control")
print("如覆盖升级，旧 config.lua 已备份为 config.lua.bak。")
