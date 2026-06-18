-- Нормализация снимка стока тикера в модель UI.
local M = {}

function M.group(id, itemGroups)
  if itemGroups and itemGroups[1] then return tostring(itemGroups[1]) end
  return id:match("^(.-):") or "other"
end

function M.normalize(raw, names)
  local out = {}
  for _, e in ipairs(raw) do
    out[#out + 1] = {
      id      = e.name,
      count   = e.count or 0,
      display = names.label(e.name, e.displayName),
      group   = M.group(e.name, e.itemGroups),
    }
  end
  table.sort(out, function(a, b) return a.display:lower() < b.display:lower() end)
  return out
end

function M.groups(entries)
  local seen, list = {}, {}
  for _, e in ipairs(entries) do
    if not seen[e.group] then
      seen[e.group] = true
      list[#list + 1] = e.group
    end
  end
  table.sort(list)
  table.insert(list, 1, "All")
  return list
end

return M
