-- Таксономия предметов: id+tags → семантическая категория с фиксированным порядком.
-- Чистый модуль (без I/O), юнит-тестируем. Правила хардкод (правятся здесь).
local M = {}

-- Порядок ОТОБРАЖЕНИЯ (ранг). Источник истины для сортировки сайдбара.
M.CATS = {
  { name = "Create",    rank = 1 },
  { name = "Redstone",  rank = 2 },
  { name = "Resources", rank = 3 },
  { name = "Wood",      rank = 4 },
  { name = "Stone",     rank = 5 },
  { name = "Building",  rank = 6 },
  { name = "Other",     rank = 7 },
}

local RANK = {}
for _, c in ipairs(M.CATS) do RANK[c.name] = c.rank end

-- множество тегов из массива (или пустое)
local function tagset(tags)
  local s = {}
  if tags then for _, t in ipairs(tags) do s[tostring(t)] = true end end
  return s
end

-- любой тег с заданным префиксом ("c:ingots", "minecraft:logs", "forge:")
local function hasTagPrefix(set, prefix)
  for t in pairs(set) do if t:sub(1, #prefix) == prefix then return true end end
  return false
end

-- любая подстрока id из списка
local function idAny(id, subs)
  for _, s in ipairs(subs) do if id:find(s, 1, true) then return true end end
  return false
end

-- Правила в ПОРЯДКЕ МАТЧИНГА (первое совпавшее побеждает). Порядок ≠ ранг.
-- Create → Redstone → Wood → Resources → Stone → Building → Other.
local RULES = {
  { "Create", function(id) return id:find("create", 1, true) ~= nil end },

  { "Redstone", function(id)
    if id:find("ore", 1, true) then return false end -- redstone_ore → Resources
    return idAny(id, {
      "redstone", "repeater", "comparator", "observer", "piston", "lever",
      "hopper", "dropper", "dispenser", "target", "tripwire", "daylight_detector",
      "note_block", "button", "pressure_plate", "_rail", "rail",
    })
  end },

  { "Wood", function(id, set)
    if hasTagPrefix(set, "minecraft:logs") or hasTagPrefix(set, "minecraft:planks") then return true end
    return idAny(id, { "_log", "_wood", "_planks", "_stem", "_hyphae", "stripped_", "bamboo" })
  end },

  { "Resources", function(id, set)
    if hasTagPrefix(set, "c:ingots") or hasTagPrefix(set, "c:nuggets")
      or hasTagPrefix(set, "c:gems") or hasTagPrefix(set, "c:ores")
      or hasTagPrefix(set, "c:dusts") or hasTagPrefix(set, "c:raw_materials")
      or hasTagPrefix(set, "forge:") then return true end
    return idAny(id, {
      "ingot", "nugget", "raw_", "_ore", "dust", "coal", "charcoal", "diamond",
      "emerald", "lapis", "quartz", "netherite", "amethyst", "string", "leather",
      "gunpowder", "blaze", "ender_pearl", "flint",
    })
  end },

  { "Stone", function(id)
    return idAny(id, {
      "stone", "cobble", "deepslate", "granite", "diorite", "andesite", "tuff",
      "basalt", "blackstone", "sandstone", "gravel", "dirt", "netherrack",
      "end_stone", "calcite",
    })
  end },

  { "Building", function(id)
    return idAny(id, {
      "bricks", "concrete", "terracotta", "glass", "wool", "prismarine",
      "purpur", "slab", "stairs", "wall", "fence", "_block",
    })
  end },
}

-- id → имя категории
function M.of(id, tags)
  id = tostring(id)
  local set = tagset(tags)
  for _, rule in ipairs(RULES) do
    if rule[2](id, set) then return rule[1] end
  end
  return "Other"
end

-- имя категории → ранг (для сортировки). Неизвестное → в конец.
function M.order(name)
  return RANK[name] or 99
end

return M
