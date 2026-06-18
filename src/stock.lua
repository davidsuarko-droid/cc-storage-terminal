-- Нормализация снимка стока тикера в модель UI.
local classify = require("classify")
local M = {}

function M.normalize(raw, names)
  local out = {}
  for _, e in ipairs(raw) do
    out[#out + 1] = {
      id      = e.name,
      count   = e.count or 0,
      display = names.label(e.name, e.displayName),
      group   = classify.of(e.name, e.tags),
    }
  end
  table.sort(out, function(a, b) return a.display:lower() < b.display:lower() end)
  return out
end

-- уникальные встреченные группы, сортированы по рангу таксономии, "All" первым
function M.groups(entries)
  local seen, list = {}, {}
  for _, e in ipairs(entries) do
    if not seen[e.group] then
      seen[e.group] = true
      list[#list + 1] = e.group
    end
  end
  table.sort(list, function(a, b)
    local ra, rb = classify.order(a), classify.order(b)
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  table.insert(list, 1, "All")
  return list
end

return M
