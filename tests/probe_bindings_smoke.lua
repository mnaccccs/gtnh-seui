-- probe_bindings.lua smoke test with mocked OC components
package.path = "./?.lua;./?/init.lua;" .. package.path

local minerAddress = "11111111-1111-1111-1111-111111111111"
local transposerAddress = "22222222-2222-2222-2222-222222222222"

local miner = {
  getName = function() return "gt.blockmachines.multimachine.projectmoduleminert3" end,
}
local transposer = {
  getInventorySize = function(side)
    if side == 0 then return 27 end
    if side == 1 then return 1 end
    return nil, "no inventory"
  end,
  getInventoryName = function(side)
    return side == 0 and "shared_drone_chest" or "miner_input"
  end,
  getAllStacks = function(side)
    return {
      getAll = function()
        if side == 0 then
          return { [0] = {name="gtnhintergalactic:item.MiningDrone", damage=2, size=4} }
        end
        return { [0] = {name="minecraft:cobblestone", label="圆石", size=1} }
      end,
    }
  end,
}

local function iterator(values)
  local i = 0
  return function()
    i = i + 1
    return values[i]
  end
end

package.preload["component"] = function()
  return {
    list = function(ctype)
      if ctype == "gt_machine" then return iterator({minerAddress}) end
      if ctype == "transposer" then return iterator({transposerAddress}) end
      return iterator({})
    end,
    proxy = function(address)
      if address == minerAddress then return miner end
      if address == transposerAddress then return transposer end
      error("unknown address")
    end,
  }
end

local output = {}
local realPrint = print
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  output[#output + 1] = table.concat(parts, "\t")
end

local ok, err = pcall(dofile, "probe_bindings.lua")
print = realPrint
assert(ok, err)

local text = table.concat(output, "\n")
assert(text:find(minerAddress, 1, true), "missing miner full address")
assert(text:find(transposerAddress, 1, true), "missing transposer full address")
assert(text:find("MK-3无人机×4", 1, true), "missing drone inventory summary")
assert(text:find("sides.down", 1, true), "missing side mapping")
assert(not text:find("minerBindings", 1, true), "probe must not request per-miner bindings")
realPrint("probe_bindings smoke: ALL PASSED")
