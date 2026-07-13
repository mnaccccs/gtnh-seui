-- SEUI lib/format.lua
-- 数值格式化、Unicode 截断与填充

local unicode = require("unicode")

local M = {}

-- SI 数量缩写
function M.formatAmount(n)
  n = tonumber(n) or 0
  local abs = math.abs(n)
  if abs >= 1e15 then return string.format("%.2fP", n / 1e15)
  elseif abs >= 1e12 then return string.format("%.2fT", n / 1e12)
  elseif abs >= 1e9 then  return string.format("%.2fG", n / 1e9)
  elseif abs >= 1e6 then  return string.format("%.2fM", n / 1e6)
  elseif abs >= 1e3 then  return string.format("%.2fK", n / 1e3)
  else return tostring(math.floor(n))
  end
end

-- OpenComputers 1.12.44 的 unicode.wtrunc 在请求宽度大于字符串实际宽度时
-- 会越过字符串末尾并抛出 `index N, length N`。它使用严格截断阈值，
-- 所以要先测宽；确需截断时传 width+1，才能保留恰好装得下的末字符。
local function truncateToWidth(text, width)
  text = tostring(text or "")
  width = math.max(0, math.floor(tonumber(width) or 0))
  if width == 0 then return "", 0 end
  local current = unicode.wlen(text)
  if current <= width then return text, current end
  local truncated = unicode.wtrunc(text, width + 1)
  return truncated, unicode.wlen(truncated)
end

-- 将文本截断/填充到指定显示宽度
function M.fit(text, width)
  width = math.max(0, math.floor(tonumber(width) or 0))
  local textWidth
  text, textWidth = truncateToWidth(text, width)
  local pad = width - textWidth
  if pad > 0 then
    return text .. string.rep(" ", pad)
  end
  return text
end

-- 右对齐
function M.fitRight(text, width)
  width = math.max(0, math.floor(tonumber(width) or 0))
  local textWidth
  text, textWidth = truncateToWidth(text, width)
  local pad = width - textWidth
  if pad > 0 then
    return string.rep(" ", pad) .. text
  end
  return text
end

-- 居中
function M.fitCenter(text, width)
  width = math.max(0, math.floor(tonumber(width) or 0))
  local textWidth
  text, textWidth = truncateToWidth(text, width)
  local pad = width - textWidth
  if pad > 0 then
    local left = math.floor(pad / 2)
    local right = pad - left
    return string.rep(" ", left) .. text .. string.rep(" ", right)
  end
  return text
end

-- 解析 "10M" / "1.5G" / "500T" / "12345" 为数字
function M.parseSize(str)
  str = tostring(str or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if str == "" then return nil, "empty" end
  local num, suffix = str:match("^(%d+%.?%d*)%s*([kmgtpl]?)$")
  if not num then return nil, "parse error" end
  local n = tonumber(num)
  if not n then return nil, "not a number" end
  local mult = 1
  if suffix == "k" then mult = 1e3
  elseif suffix == "m" then mult = 1e6
  elseif suffix == "g" then mult = 1e9
  elseif suffix == "t" then mult = 1e12
  elseif suffix == "p" then mult = 1e15
  end
  local result = n * mult
  if result < 0 then return nil, "negative" end
  if result > 9e15 then return nil, "too large" end
  return result
end

-- 安全的整数除法 (Lua 5.2/5.3 兼容)
function M.intDiv(a, b)
  return math.floor(a / b)
end

-- clamp
function M.clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- 时间格式化 mm:ss
function M.formatDuration(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local m = math.floor(seconds / 60)
  local s = seconds % 60
  return string.format("%d:%02d", m, s)
end

-- 提取 itemKey
function M.itemKey(name, damage)
  return tostring(name) .. ":" .. tostring(damage or 0)
end

-- 旧 packed batch 解码
-- v1 简单格式：流体 planetType*1000+gasType, 矿物 droneTier*1000+distance
-- v2.2 扩展矿物：droneTier*100000000 + distance*100000 + overdrive*10000
function M.decodePackedBatch(packed, isFluid, profile)
  packed = tonumber(packed) or 0
  -- 检查停止标记
  local stopAfter = false
  -- 100000 标记只属于 v1 简单格式。v2.2 正常编码本来就远大于它。
  if profile ~= "v2.2_extended" and packed >= 100000 then
    stopAfter = true
    packed = packed - 100000
  end

  if isFluid then
    local planet = M.intDiv(packed, 1000) % 100
    local gas = packed % 1000
    return { planetType = planet, gasType = gas, stopAfter = stopAfter }
  end

  if profile == "v2.2_extended" then
    local droneTier = M.intDiv(packed, 100000000)
    local distance = M.intDiv(packed, 100000) % 1000
    local overdrive = (packed % 100000) / 10000
    return { droneTier = droneTier, distance = distance, overdrive = overdrive, stopAfter = stopAfter }
  else
    local droneTier = M.intDiv(packed, 1000)
    local distance = packed % 1000
    return { droneTier = droneTier, distance = distance, stopAfter = stopAfter }
  end
end

return M
