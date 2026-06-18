-- Чистая UI-логика: фильтры, хит-тест, раскладка. Без I/O.
local M = {}

function M.filter(entries, query)
  if not query or query == "" then return entries end
  local q = query:lower()
  local out = {}
  for _, e in ipairs(entries) do
    if e.display:lower():find(q, 1, true) or e.id:lower():find(q, 1, true) then
      out[#out + 1] = e
    end
  end
  return out
end

function M.byGroup(entries, group)
  if not group or group == "All" then return entries end
  local out = {}
  for _, e in ipairs(entries) do
    if e.group == group then out[#out + 1] = e end
  end
  return out
end

function M.inside(rect, x, y)
  return x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2
end

function M.clampQty(n, max)
  if max < 1 then return 0 end
  if n < 1 then return 1 end
  if n > max then return max end
  return n
end

function M.layout(w, h)
  local catW = 12
  return {
    search = { x1 = 1,        y1 = 1, x2 = w,    y2 = 1 },
    cats   = { x1 = 1,        y1 = 2, x2 = catW, y2 = h - 1 },
    grid   = { x1 = catW + 1, y1 = 2, x2 = w,    y2 = h - 1 },
    addr   = { x1 = 1,        y1 = h, x2 = w,    y2 = h },
  }
end

return M
