-- GTNH 2.9.0-beta-1 太空钻机全部 40 种流体目录
-- 路由和基础抽取速度来自 GT5-Unofficial 5.09.52.594 SpacePumpingRecipes。

local M = {}

M.entries = {
  {2,1,"氯苯",896000,{"chlorobenzene"}},
  {3,1,"末影黏浆",32000,{"endergoo","ender_goo"}},
  {3,2,"极重油",1400000,{"oil.extraheavy","extraheavyoil","heavy_oil"}},
  {3,3,"岩浆",1800000,{"lava"}},
  {3,4,"天然气",1400000,{"naturalgas","natural_gas"}},
  {4,1,"硫酸",784000,{"sulfuricacid","sulfuric_acid"}},
  {4,2,"熔融铁",896000,{"molten.iron","molten_iron"}},
  {4,3,"石油",1400000,{"oil"}},
  {4,4,"重油",1792000,{"oilheavy","heavy_oil"}},
  {4,5,"熔融铅",896000,{"molten.lead","molten_lead"}},
  {4,6,"原油",1400000,{"oilmedium","raw_oil"}},
  {4,7,"轻油",780000,{"oillight","light_oil"}},
  {4,8,"二氧化碳",1680000,{"carbondioxide","carbon_dioxide"}},
  {5,1,"一氧化碳",4480000,{"carbonmonoxide","carbon_monoxide"}},
  {5,2,"氦-3",2800000,{"helium-3","helium3"}},
  {5,3,"盐水",2800000,{"saltwater","salt_water"}},
  {5,4,"氦气",1400000,{"helium"}},
  {5,5,"液态氧",896000,{"liquidoxygen","liquid_oxygen"}},
  {5,6,"氖",32000,{"neon"}},
  {5,7,"氩气",32000,{"argon"}},
  {5,8,"氪",8000,{"krypton"}},
  {5,9,"甲烷",1792000,{"methane"}},
  {5,10,"硫化氢",392000,{"hydrogensulfide","hydrogen_sulfide"}},
  {5,11,"乙烷",1194000,{"ethane"}},
  {6,1,"氘",1568000,{"deuterium"}},
  {6,2,"氚",240000,{"tritium"}},
  {6,3,"氨气",240000,{"ammonia"}},
  {6,4,"氙",16000,{"xenon"}},
  {6,5,"乙烯",1792000,{"ethylene"}},
  {7,1,"氢氟酸",672000,{"hydrofluoricacid","hydrofluoric_acid"}},
  {7,2,"氟",1792000,{"fluorine"}},
  {7,3,"氮气",1792000,{"nitrogen"}},
  {7,4,"氧气",1792000,{"oxygen"}},
  {8,1,"氢气",1568000,{"hydrogen"}},
  {8,2,"液态空气",875000,{"liquidair","liquid_air"}},
  {8,3,"熔融铜",672000,{"molten.copper","molten_copper"}},
  {8,4,"不明液体",672000,{"unknowwater","unknown_liquid"}},
  {8,5,"蒸馏水",17920000,{"ic2distilledwater","distilledwater","distilled_water"}},
  {8,6,"氡",64000,{"radon"}},
  {8,7,"熔融锡",672000,{"molten.tin","molten_tin"}},
}

function M.routeKey(planet, gas)
  return tostring(tonumber(planet) or 0) .. ":" .. tostring(tonumber(gas) or 0)
end

function M.populate(model)
  local existing = {}
  for _, t in ipairs(model.getTargets()) do
    if t.domain == "pump" and t.route then
      existing[M.routeKey(t.route.planetType, t.route.gasType)] = t
    end
  end
  local added = 0
  for order, e in ipairs(M.entries) do
    local planet, gas, label, rate, aliases = e[1],e[2],e[3],e[4],e[5]
    local found = existing[M.routeKey(planet, gas)]
    if found then
      found.fluidAliases = found.fluidAliases or aliases
      found.route.baseRate = found.route.baseRate or rate
    else
      model.addTarget{
        id="pump:"..planet..":"..gas, domain="pump", label=label,
        fluid=aliases[1], fluidAliases=aliases, mode="OFF", target=0,
        order=order, route={planetType=planet,gasType=gas,baseRate=rate,maxBatch=30},
      }
      added=added+1
    end
  end
  return added
end

return M
