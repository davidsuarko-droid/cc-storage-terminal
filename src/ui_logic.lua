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

-- Раскладка зон грид-магазина. title(y1, кнопка адреса справа), search(y2),
-- горизонтальные чипы категорий(y3), грид плиток на всю ширину(y4..h-2),
-- скролл-строка со стрелками (y=h-1), статус(y=h).
function M.layout(w, h)
  local addrW = math.min(20, w - 1)
  return {
    title  = { x1 = 1,             y1 = 1,     x2 = w, y2 = 1 },
    addr   = { x1 = w - addrW + 1, y1 = 1,     x2 = w, y2 = 1 },
    search = { x1 = 1,             y1 = 2,     x2 = w, y2 = 2 },
    chips  = { x1 = 1,             y1 = 3,     x2 = w, y2 = 4 },
    grid   = { x1 = 1,             y1 = 5,     x2 = w, y2 = h - 2 },
    up     = { x1 = w - 9,         y1 = h - 1, x2 = w - 5, y2 = h - 1 },
    down   = { x1 = w - 4,         y1 = h - 1, x2 = w, y2 = h - 1 },
    status = { x1 = 1,             y1 = h,     x2 = w, y2 = h },
  }
end

-- Сколько плиток влезает в grid. Возвращает {cols, rows, tileW, tileH, gap, perPage}.
function M.gridDims(grid, tileW, tileH, gap)
  local gw = grid.x2 - grid.x1 + 1
  local gh = grid.y2 - grid.y1 + 1
  local cols = math.max(1, math.floor((gw + gap) / (tileW + gap)))
  local rows = math.max(1, math.floor((gh + gap) / (tileH + gap)))
  return { cols = cols, rows = rows, tileW = tileW, tileH = tileH, gap = gap, perPage = cols * rows }
end

-- Позиции плиток текущей страницы. origin = {x, y} (левый-верх grid).
-- Возвращает (список {entry, rect}, page-инфо из M.page).
function M.tiles(items, scroll, dims, origin)
  local pg = M.page(items, scroll, dims.perPage)
  local step = { x = dims.tileW + dims.gap, y = dims.tileH + dims.gap }
  local out = {}
  for i, e in ipairs(pg.slice) do
    local idx = i - 1
    local col = idx % dims.cols
    local row = math.floor(idx / dims.cols)
    local x1 = origin.x + col * step.x
    local y1 = origin.y + row * step.y
    out[i] = { entry = e, rect = { x1 = x1, y1 = y1, x2 = x1 + dims.tileW - 1, y2 = y1 + dims.tileH - 1 } }
  end
  return out, pg
end

-- Горизонтальная раскладка чипов категорий с обрезкой по maxW.
-- height = высота чипа (тап-зона), по умолчанию 1.
function M.chips(groups, x, y, maxW, height)
  height = height or 1
  local out = {}
  local cx = x
  for _, g in ipairs(groups) do
    local label = " " .. g .. " "
    local wlab = #label
    if cx - x + wlab > maxW then break end
    out[#out + 1] = { group = g, label = label,
      rect = { x1 = cx, y1 = y, x2 = cx + wlab - 1, y2 = y + height - 1 } }
    cx = cx + wlab + 1
  end
  return out
end

-- Перенос строки s на 2 строки шириной w (по словам; режет длинное слово).
-- Возвращает {line1, line2}. Вторая обрезается с ".." если не влезла.
function M.wrap2(s, w)
  if w <= 0 then return { "", "" } end
  if #s <= w then return { s, "" } end
  -- ищем пробел для разрыва первой строки в пределах w
  local cut = nil
  for i = w, 1, -1 do
    if s:sub(i, i) == " " then cut = i; break end
  end
  local l1, rest
  if cut and cut > 1 then
    l1 = s:sub(1, cut - 1)
    rest = s:sub(cut + 1)
  else
    l1 = s:sub(1, w)
    rest = s:sub(w + 1)
  end
  if #rest > w then
    rest = w > 2 and (rest:sub(1, w - 2) .. "..") or rest:sub(1, w)
  end
  return { l1, rest }
end

-- === Корзина (накопление заказа, как лог-запросы Factorio) ===
-- Модель: { order = {id,...}, map = { id = {entry=, qty=} } }. Сохраняет порядок.

function M.basketNew()
  return { order = {}, map = {} }
end

-- Изменить кол-во id на delta (может быть <0). Кламп [0, entry.count].
-- При 0 — убрать из корзины. Возвращает итоговое qty.
function M.basketAdd(basket, entry, delta)
  local cur = basket.map[entry.id]
  local qty = (cur and cur.qty or 0) + delta
  if qty < 0 then qty = 0 end
  if qty > entry.count then qty = entry.count end
  if qty == 0 then
    if cur then
      basket.map[entry.id] = nil
      for i, id in ipairs(basket.order) do
        if id == entry.id then table.remove(basket.order, i); break end
      end
    end
    return 0
  end
  if not cur then
    basket.order[#basket.order + 1] = entry.id
    basket.map[entry.id] = { entry = entry, qty = qty }
  else
    cur.qty = qty
    cur.entry = entry -- освежить (сток мог поменяться)
  end
  return qty
end

function M.basketQty(basket, id)
  local c = basket.map[id]
  return c and c.qty or 0
end

-- Список {entry, qty} в порядке добавления.
function M.basketList(basket)
  local out = {}
  for _, id in ipairs(basket.order) do
    local c = basket.map[id]
    if c then out[#out + 1] = { entry = c.entry, qty = c.qty } end
  end
  return out
end

-- Итоги: lines = позиций, units = суммарно штук.
function M.basketTotals(basket)
  local lines, units = 0, 0
  for _, id in ipairs(basket.order) do
    local c = basket.map[id]
    if c then lines = lines + 1; units = units + c.qty end
  end
  return { lines = lines, units = units }
end

-- Цикл шага накопления для тач-монитора: 1 → 8 → 64 → 1.
function M.nextStep(step)
  if step == 1 then return 8
  elseif step == 8 then return 64
  else return 1 end
end

-- Степпер количества: применить кнопку к value, кламп в [0, max].
function M.stepper(value, key, max)
  if key == "-" then value = value - 1
  elseif key == "+" then value = value + 1
  elseif key == "+8" then value = value + 8
  elseif key == "+64" then value = value + 64
  elseif key == "Max" then value = max
  elseif key == "Clear" then value = 0 end
  if value < 0 then value = 0 end
  if value > max then value = max end
  return value
end

return M
