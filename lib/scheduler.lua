-- SEUI lib/scheduler.lua
-- 调度器：为每个 domain 独立选择最优候选目标

local log = require("lib.log")
local model = require("lib.model")
local format = require("lib.format")

local M = {}

-- 评分计算
local function computeScore(target)
  local available = math.max(0, target.current + target.pending)
  local deficit = 0
  if target.target > 0 then
    deficit = math.max(0, 1 - (available / target.target))
  elseif target.mode == "ALWAYS" then
    deficit = 0.5  -- ALWAYS 无缺口概念，给固定中性分
  end
  local score = deficit * 100 + (target.weight or 0)
  return score, deficit
end

-- 候选筛选
local function buildCandidates(targets, now)
  local lowTargets = {}
  local alwaysTargets = {}

  for _, t in ipairs(targets) do
    local route = t.route or {}
    local routable
    if t.domain == "pump" then
      routable = tonumber(route.planetType) and tonumber(route.planetType) > 0
          and tonumber(route.gasType) and tonumber(route.gasType) > 0
    else
      routable = tonumber(route.droneTier) and tonumber(route.droneTier) > 0
          and tonumber(route.distance) and tonumber(route.distance) >= 0
    end

    if not routable and t.mode ~= "OFF" then
      t.runtime.state = "FAULT"
      t.runtime.lastError = "invalid route"
    elseif t.mode == "TARGET" then
      local ratio = model.getRatio(t)
      -- 未运行目标低于 lowRatio 才启动；已运行目标保持到 highRatio 才停止。
      local shouldRun = ratio < t.lowRatio
          or (t.runtime.state == "RUN" and ratio < t.highRatio)
      if t.target > 0 and shouldRun then
        local score, deficit = computeScore(t)
        table.insert(lowTargets, { target = t, score = score, deficit = deficit })
      end
    elseif t.mode == "ALWAYS" then
      local score, deficit = computeScore(t)
      table.insert(alwaysTargets, { target = t, score = score, deficit = deficit })
    end
    -- OFF 不进入候选
  end

  -- LOW 层优先；空时取 ALWAYS
  local candidates = #lowTargets > 0 and lowTargets or alwaysTargets

  -- 排序：分数降序，order 升序，lastServed 升序
  table.sort(candidates, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.target.order ~= b.target.order then return a.target.order < b.target.order end
    return (a.target.runtime.lastServed or 0) < (b.target.runtime.lastServed or 0)
  end)

  return candidates
end

-- 为 domain 生成任务
-- workers: 该 domain 的机器列表
-- compatAllOneTarget: 兼容模式，所有机器追同一目标
function M.plan(domain, targets, workers, now, config)
  local candidates = buildCandidates(targets, now)
  if #candidates == 0 then
    return nil, "no candidates"
  end

  local best = candidates[1]
  local target = best.target

  local assignments = {}
  if domain == "pump" then
    if config and config.compatAllPumpsOneTarget then
      -- 所有泵追同一目标
      for _, pump in ipairs(workers) do
        table.insert(assignments, {
          worker = pump,
          domain = "pump",
          target = target,
          recipe = 0,  -- 所有 recipe 指同一目标
          params = {
            planetType = target.route.planetType or 0,
            gasType = target.route.gasType or 0,
          },
          batch = config.maxBatch or 30,
        })
      end
    else
      -- 高级模式：每个 recipe 分配不同候选
      -- 第一版暂不实现，回退到兼容模式
      for _, pump in ipairs(workers) do
        table.insert(assignments, {
          worker = pump,
          domain = "pump",
          target = target,
          recipe = 0,
          params = {
            planetType = target.route.planetType or 0,
            gasType = target.route.gasType or 0,
          },
          batch = config.maxBatch or 30,
        })
      end
    end

  elseif domain == "miner" then
    if config and config.compatAllMinersOneTarget then
      for _, miner in ipairs(workers) do
        table.insert(assignments, {
          worker = miner,
          domain = "miner",
          target = target,
          params = {
            distance = target.route.distance or 0,
            droneTier = target.route.droneTier or 1,
            parallel = target.route.parallel,
          },
        })
      end
    else
      for _, miner in ipairs(workers) do
        table.insert(assignments, {
          worker = miner,
          domain = "miner",
          target = target,
          params = {
            distance = target.route.distance or 0,
            droneTier = target.route.droneTier or 1,
            parallel = target.route.parallel,
          },
        })
      end
    end
  end

  log.info("scheduler", string.format(
    "%s selected %s class=%s deficit=%.3f weight=%d score=%.1f order=%d",
    domain:upper(), target.id,
    target.mode == "ALWAYS" and "ALWAYS" or "LOW",
    best.deficit, target.weight or 0, best.score, target.order
  ))

  return assignments
end

return M
