-- Чистая UI-логика: фильтры, хит-тест, раскладка, пагинация. Без I/O.
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

-- Пагинация списка. rows = видимых строк. Клампит scroll в [0, max].
-- Возвращает { slice, scroll, hasUp, hasDown }.
function M.page(items, scroll, rows)
  local n = #items
  local maxScroll = math.max(0, n - rows)
  if scroll < 0 then scroll = 0 end
  if scroll > maxScroll then scroll = maxScroll end
  local slice = {}
  for i = scroll + 1, math.min(scroll + rows, n) do
    slice[#slice + 1] = items[i]
  end
  return {
    slice   = slice,
    scroll  = scroll,
    hasUp   = scroll > 0,
    hasDown = scroll + rows < n,
  }
end

-- Раскладка зон. title(y1) с кнопкой адреса справа, search(y2),
-- cats слева (ширина catW), grid справа, scroll-бар (y=h-1), status(y=h).
function M.layout(w, h)
  local catW = 14
  local addrW = math.min(20, w - 1)
  return {
    title  = { x1 = 1,        y1 = 1,     x2 = w,    y2 = 1 },
    addr   = { x1 = w - addrW + 1, y1 = 1, x2 = w,   y2 = 1 },
    search = { x1 = 1,        y1 = 2,     x2 = w,    y2 = 2 },
    cats   = { x1 = 1,        y1 = 3,     x2 = catW, y2 = h - 1 },
    grid   = { x1 = catW + 1, y1 = 3,     x2 = w,    y2 = h - 2 },
    up     = { x1 = catW + 1, y1 = h - 1, x2 = catW + 5, y2 = h - 1 },
    down   = { x1 = w - 4,    y1 = h - 1, x2 = w,    y2 = h - 1 },
    status = { x1 = 1,        y1 = h,     x2 = w,    y2 = h },
  }
end

return M
