-- Рендер модели на монитор. Палитра по DESIGN.md (минимализм, синий точечно).
-- Весь chrome — English ASCII (шрифт CC не умеет кириллицу). Возвращает хит-зоны.
local ui_logic = require("ui_logic")
local M = {}

-- палитра (DESIGN → CC colors)
local C = {
  bg     = colors.white,
  surf   = colors.lightGray, -- surface / чередование строк
  text   = colors.black,
  muted  = colors.gray,
  accent = colors.blue,      -- активное/акцент, точечно
  on     = colors.white,     -- текст на акценте
  danger = colors.red,
  edge_l = colors.white,     -- bevel: верх/лево
  edge_d = colors.gray,      -- bevel: низ/право
}

local function fill(mon, rect, bg)
  mon.setBackgroundColor(bg)
  local blank = string.rep(" ", rect.x2 - rect.x1 + 1)
  for y = rect.y1, rect.y2 do
    mon.setCursorPos(rect.x1, y)
    mon.write(blank)
  end
end

local function text(mon, x, y, s, fg, bg)
  mon.setCursorPos(x, y)
  mon.setTextColor(fg)
  mon.setBackgroundColor(bg)
  mon.write(s)
end

-- обрезка с ".." если длиннее max
local function trunc(s, max)
  if #s <= max then return s end
  if max <= 2 then return s:sub(1, max) end
  return s:sub(1, max - 2) .. ".."
end

function M.draw(monitor, model)
  monitor.setTextScale(0.5)
  local w, h = monitor.getSize()
  local L = ui_logic.layout(w, h)
  fill(monitor, { x1 = 1, y1 = 1, x2 = w, y2 = h }, C.bg)
  local hit = { cats = {}, items = {}, keypad = {} }

  -- title bar: STORAGE слева + кнопка адреса справа (синяя, точечный акцент)
  fill(monitor, L.title, C.surf)
  text(monitor, 2, 1, "STORAGE", C.text, C.surf)
  local addrLabel = " Deliver: " .. model.address .. " > "
  addrLabel = trunc(addrLabel, L.addr.x2 - L.addr.x1 + 1)
  fill(monitor, L.addr, C.accent)
  text(monitor, L.addr.x2 - #addrLabel + 1, 1, addrLabel, C.on, C.accent)
  hit.addr = L.addr

  -- search bar (focus → синяя обводка)
  local focused = model.searchFocus
  local sbg = focused and C.accent or C.bg
  local sfg = focused and C.on or C.text
  fill(monitor, L.search, sbg)
  local q = model.query ~= "" and model.query or "type to filter..."
  text(monitor, L.search.x1 + 1, 2, "Search: " .. q, sfg, sbg)
  local cnt = "#" .. #model.items
  text(monitor, L.search.x2 - #cnt, 2, cnt, focused and C.on or C.muted, sbg)
  hit.search = L.search

  -- категории (сайдбар, порядок по рангу из stock.groups)
  fill(monitor, L.cats, C.bg)
  local cw = L.cats.x2 - L.cats.x1 + 1
  local cy = L.cats.y1
  for _, g in ipairs(model.groups) do
    if cy > L.cats.y2 then break end
    local active = (g == model.group)
    local bg = active and C.accent or C.surf
    local fg = active and C.on or C.text
    local rect = { x1 = L.cats.x1, y1 = cy, x2 = L.cats.x2, y2 = cy }
    fill(monitor, rect, bg)
    text(monitor, L.cats.x1 + 1, cy, trunc(g, cw - 1), fg, bg)
    hit.cats[#hit.cats + 1] = { rect = rect, group = g }
    cy = cy + 1
  end

  -- сетка предметов со скроллом + чередованием фона
  local rows = L.grid.y2 - L.grid.y1 + 1
  local pg = ui_logic.page(model.items, model.scroll or 0, rows)
  model.scroll = pg.scroll
  local gw = L.grid.x2 - L.grid.x1 + 1
  for i, e in ipairs(pg.slice) do
    local gy = L.grid.y1 + i - 1
    local rect = { x1 = L.grid.x1, y1 = gy, x2 = L.grid.x2, y2 = gy }
    local rbg = (i % 2 == 1) and C.bg or C.surf
    fill(monitor, rect, rbg)
    local cstr = "x" .. e.count
    local nameMax = gw - #cstr - 2
    text(monitor, L.grid.x1 + 1, gy, trunc(e.display, nameMax), C.text, rbg)
    text(monitor, L.grid.x2 - #cstr, gy, cstr, C.muted, rbg)
    hit.items[#hit.items + 1] = { rect = rect, entry = e }
  end

  -- скролл-бар (y=h-1): [^]  page X-Y/Z  [v]
  fill(monitor, { x1 = L.cats.x1, y1 = L.up.y1, x2 = w, y2 = L.up.y1 }, C.surf)
  if pg.hasUp then
    text(monitor, L.up.x1, L.up.y1, " [^] ", C.text, C.surf)
    hit.up = L.up
  else
    text(monitor, L.up.x1, L.up.y1, " [ ] ", C.muted, C.surf)
  end
  if pg.hasDown then
    text(monitor, L.down.x1, L.down.y1, " [v] ", C.text, C.surf)
    hit.down = L.down
  else
    text(monitor, L.down.x1, L.down.y1, " [ ] ", C.muted, C.surf)
  end
  local total = #model.items
  local shown = math.min((model.scroll or 0) + rows, total)
  local pginfo = (math.min((model.scroll or 0) + 1, total)) .. "-" .. shown .. "/" .. total
  text(monitor, math.floor(w / 2) - math.floor(#pginfo / 2), L.up.y1, pginfo, C.muted, C.surf)

  -- статус-бар (тост или подсказка)
  fill(monitor, L.status, C.bg)
  if model.toast then
    text(monitor, L.status.x1 + 1, L.status.y1, trunc(model.toast, w - 2), C.text, C.bg)
  else
    text(monitor, L.status.x1 + 1, L.status.y1, "Tap item to order  |  Tap deliver to switch",
      C.muted, C.bg)
  end

  -- keypad оверлей (beveled, Win95-дух)
  if model.keypad then
    local pw, ph = 18, 9
    local kx, ky = math.floor(w / 2) - math.floor(pw / 2), math.floor(h / 2) - math.floor(ph / 2)
    local panel = { x1 = kx, y1 = ky, x2 = kx + pw - 1, y2 = ky + ph - 1 }
    fill(monitor, panel, C.surf)
    -- bevel: верх/лево светлый, низ/право тёмный
    fill(monitor, { x1 = panel.x1, y1 = panel.y1, x2 = panel.x2, y2 = panel.y1 }, C.edge_l)
    fill(monitor, { x1 = panel.x1, y1 = panel.y1, x2 = panel.x1, y2 = panel.y2 }, C.edge_l)
    fill(monitor, { x1 = panel.x1, y1 = panel.y2, x2 = panel.x2, y2 = panel.y2 }, C.edge_d)
    fill(monitor, { x1 = panel.x2, y1 = panel.y1, x2 = panel.x2, y2 = panel.y2 }, C.edge_d)
    local kp = model.keypad
    text(monitor, kx + 1, ky + 1, trunc(kp.entry.display, pw - 7) .. "  x" .. kp.value,
      C.text, C.surf)
    local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "OK", "X" }
    for i, k in ipairs(keys) do
      local col = (i - 1) % 3
      local row = math.floor((i - 1) / 3)
      local bx = kx + 2 + col * 5
      local by = ky + 3 + row
      local rect = { x1 = bx, y1 = by, x2 = bx + 3, y2 = by }
      local face = C.bg
      local fg = C.text
      if k == "OK" then face = C.accent; fg = C.on
      elseif k == "X" then face = C.danger; fg = C.on end
      fill(monitor, rect, face)
      local lab = (#k == 1) and (" " .. k .. " ") or k
      text(monitor, bx + math.floor((4 - #lab) / 2), by, lab, fg, face)
      hit.keypad[#hit.keypad + 1] = { rect = rect, key = k }
    end
  end

  return hit
end

return M
