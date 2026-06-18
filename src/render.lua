-- Рендер грид-магазина. Скин Create/стимпанк: андезит-корпус + латунь-акцент.
-- Палитра перекраивается через setPaletteColour. Chrome — English ASCII
-- (шрифт CC без кириллицы). Возвращает хит-зоны.
local ui_logic = require("ui_logic")
local sprites  = require("sprites")
local M = {}

-- Семантические роли → слоты палитры CC.
local C = {
  bg       = colors.black,     -- тёмный андезит/гунметалл
  casing   = colors.gray,      -- андезит-корпус (плитка/панель)
  casingHi = colors.lightGray, -- светлый андезит (bevel верх/лево)
  casingLo = colors.black,     -- тёмный ридж (bevel низ/право)
  text     = colors.white,     -- парчмент на тёмном
  ink      = colors.black,     -- near-black на светлой плитке
  muted    = colors.gray,      -- приглушённый
  brass    = colors.yellow,    -- латунь — главный акцент
  brassHi  = colors.orange,    -- светлая латунь
  copper   = colors.red,       -- медь/ржавчина — danger/X
}

-- Цвет бейджа-спрайта по категории.
local CAT = {
  Create = colors.yellow, Redstone = colors.red, Resources = colors.lightBlue,
  Wood = colors.brown, Stone = colors.cyan, Building = colors.magenta,
  Other = colors.purple, All = colors.gray,
}

-- RGB-палитра стимпанка (применяется один раз в startup через M.applyPalette).
local PALETTE = {
  [colors.black]     = 0x2A2925, -- тёмный андезит
  [colors.gray]      = 0x8F8F86, -- андезит-корпус
  [colors.lightGray] = 0xC2C2B6, -- светлый андезит
  [colors.white]     = 0xE8DEC8, -- парчмент
  [colors.yellow]    = 0xC8A24A, -- латунь
  [colors.orange]    = 0xE3C77A, -- светлая латунь
  [colors.red]       = 0xB5512A, -- медь
  [colors.lightBlue] = 0x6E90B0, -- сталь (Resources)
  [colors.brown]     = 0x7A5A38, -- дерево
  [colors.cyan]      = 0x7E8A86, -- камень
  [colors.magenta]   = 0xB5663B, -- терракот (Building)
  [colors.purple]    = 0x6B6458, -- тусклый (Other)
}

function M.applyPalette(mon)
  if not mon.setPaletteColour then return end
  for slot, rgb in pairs(PALETTE) do mon.setPaletteColour(slot, rgb) end
end

local function fill(mon, rect, bg)
  mon.setBackgroundColor(bg)
  local blank = string.rep(" ", math.max(0, rect.x2 - rect.x1 + 1))
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

local function trunc(s, max)
  if max <= 0 then return "" end
  if #s <= max then return s end
  if max <= 2 then return s:sub(1, max) end
  return s:sub(1, max - 2) .. ".."
end

-- beveled-рамка: верх/лево hi, низ/право lo (объём корпуса).
local function bevel(mon, rect, hi, lo)
  fill(mon, { x1 = rect.x1, y1 = rect.y1, x2 = rect.x2, y2 = rect.y1 }, hi)
  fill(mon, { x1 = rect.x1, y1 = rect.y1, x2 = rect.x1, y2 = rect.y2 }, hi)
  fill(mon, { x1 = rect.x1, y1 = rect.y2, x2 = rect.x2, y2 = rect.y2 }, lo)
  fill(mon, { x1 = rect.x2, y1 = rect.y1, x2 = rect.x2, y2 = rect.y2 }, lo)
end

-- одна плитка предмета. Рамка цветом категории (различимость), тёмный зазор
-- между плитками даёт grid-gap. Имя в 2 строки. Нажатая → латунь.
local function drawTile(mon, t, model)
  local r = t.rect
  local e = t.entry
  local pressed = model.pressed == e.id
  local catColor = CAT[e.group] or C.muted
  local frame = pressed and C.brass or catColor
  local face  = pressed and C.brassHi or C.casing
  -- рамка = заливка всего прямоугольника цветом категории
  fill(mon, r, frame)
  -- внутренняя грань — корпус
  fill(mon, { x1 = r.x1 + 1, y1 = r.y1 + 1, x2 = r.x2 - 1, y2 = r.y2 - 1 }, face)
  -- спрайт категории 2x2 в левом-верхнем углу контента
  sprites.draw(mon, r.x1 + 1, r.y1 + 1, e.group, catColor, face)
  -- счётчик xN справа сверху
  local cstr = "x" .. e.count
  local cx = r.x2 - 1 - #cstr + 1
  if cx > r.x1 + 3 then text(mon, cx, r.y1 + 1, cstr, C.ink, face) end
  -- имя в 2 строки снизу
  local innerW = (r.x2 - 1) - (r.x1 + 1) + 1
  local lines = ui_logic.wrap2(e.display, innerW)
  text(mon, r.x1 + 1, r.y2 - 2, lines[1], C.ink, face)
  if lines[2] ~= "" then text(mon, r.x1 + 1, r.y2 - 1, lines[2], C.ink, face) end
end

function M.draw(monitor, model)
  monitor.setTextScale(0.5)
  local w, h = monitor.getSize()
  local L = ui_logic.layout(w, h)
  fill(monitor, { x1 = 1, y1 = 1, x2 = w, y2 = h }, C.bg)
  local hit = { tiles = {}, chips = {}, keypad = {} }

  -- title: STORAGE слева + кнопка адреса справа (латунь)
  text(monitor, 2, 1, "STORAGE", C.brass, C.bg)
  local addrLabel = " Deliver: " .. model.address .. " > "
  addrLabel = trunc(addrLabel, L.addr.x2 - L.addr.x1 + 1)
  fill(monitor, L.addr, C.brass)
  text(monitor, L.addr.x2 - #addrLabel + 1, 1, addrLabel, C.bg, C.brass)
  hit.addr = L.addr

  -- search bar
  local focused = model.searchFocus
  local sbg = focused and C.brass or C.bg
  local sfg = focused and C.bg or C.text
  fill(monitor, L.search, sbg)
  local q = model.query ~= "" and model.query or "type to filter..."
  text(monitor, L.search.x1 + 1, 2, "Search: " .. q, sfg, sbg)
  local cnt = #model.items .. " items"
  text(monitor, L.search.x2 - #cnt, 2, cnt, focused and C.bg or C.muted, sbg)
  hit.search = L.search

  -- чипы категорий (горизонталь, 2 строки высотой = крупнее тап-зона)
  fill(monitor, L.chips, C.bg)
  local chipH = L.chips.y2 - L.chips.y1 + 1
  local chips = ui_logic.chips(model.groups, L.chips.x1, L.chips.y1, w, chipH)
  for _, c in ipairs(chips) do
    local active = (c.group == model.group)
    local cbg = active and C.brass or C.casing
    local cfg = active and C.bg or C.text
    fill(monitor, c.rect, cbg)
    bevel(monitor, c.rect, active and C.brassHi or C.casingHi, C.casingLo)
    -- метка по центру вертикали чипа
    local my = c.rect.y1 + math.floor((c.rect.y2 - c.rect.y1) / 2)
    text(monitor, c.rect.x1, my, c.label, cfg, cbg)
    hit.chips[#hit.chips + 1] = { rect = c.rect, group = c.group }
  end

  -- грид плиток
  local dims = ui_logic.gridDims(L.grid, 12, 6, 1)
  local tiles, pg = ui_logic.tiles(model.items, model.scroll or 0, dims,
    { x = L.grid.x1, y = L.grid.y1 })
  model.scroll = pg.scroll
  for _, t in ipairs(tiles) do
    drawTile(monitor, t, model)
    hit.tiles[#hit.tiles + 1] = { rect = t.rect, entry = t.entry }
  end

  -- скролл-строка (y=h-1): page X/Y + стрелки справа
  fill(monitor, { x1 = 1, y1 = L.up.y1, x2 = w, y2 = L.up.y1 }, C.bg)
  local total = #model.items
  local page = math.floor((model.scroll or 0) / dims.perPage) + 1
  local pages = math.max(1, math.ceil(total / dims.perPage))
  local pginfo = total .. " items   page " .. page .. "/" .. pages
  text(monitor, 2, L.up.y1, pginfo, C.muted, C.bg)
  if pg.hasUp then
    fill(monitor, L.up, C.brass); text(monitor, L.up.x1 + 1, L.up.y1, " [^] ", C.bg, C.brass)
    hit.up = L.up
  else
    text(monitor, L.up.x1 + 1, L.up.y1, " [^] ", C.casing, C.bg)
  end
  if pg.hasDown then
    fill(monitor, L.down, C.brass); text(monitor, L.down.x1, L.down.y1, " [v] ", C.bg, C.brass)
    hit.down = L.down
  else
    text(monitor, L.down.x1, L.down.y1, " [v] ", C.casing, C.bg)
  end

  -- статус-бар (тост или подсказка)
  fill(monitor, L.status, C.bg)
  if model.toast then
    text(monitor, 2, L.status.y1, trunc(model.toast, w - 2), C.brassHi, C.bg)
  else
    text(monitor, 2, L.status.y1, "Tap tile to order  |  Tap chip to filter", C.muted, C.bg)
  end

  -- степпер-кейпад (оверлей, латунный корпус-пульт)
  if model.keypad then
    local kp = model.keypad
    local pw, ph = 21, 8
    local kx = math.floor(w / 2) - math.floor(pw / 2)
    local ky = math.floor(h / 2) - math.floor(ph / 2)
    local panel = { x1 = kx, y1 = ky, x2 = kx + pw - 1, y2 = ky + ph - 1 }
    fill(monitor, panel, C.casing)
    bevel(monitor, panel, C.casingHi, C.casingLo)
    text(monitor, kx + 2, ky + 1, trunc(kp.entry.display, pw - 4), C.ink, C.casing)
    text(monitor, kx + 2, ky + 2, "Qty: " .. kp.value .. " / " .. kp.entry.count, C.ink, C.casing)
    -- кнопка X в правом-верхнем углу
    local xrect = { x1 = panel.x2 - 2, y1 = panel.y1, x2 = panel.x2, y2 = panel.y1 }
    fill(monitor, xrect, C.copper); text(monitor, xrect.x1, xrect.y1, "[X]", C.text, C.copper)
    hit.keypad[#hit.keypad + 1] = { rect = xrect, key = "X" }
    -- ряды кнопок: {label,key,relx,rely,wbtn}
    local btns = {
      { " - ", "-", 2, 4, 3 }, { "  73 ", nil, 6, 4, 6 }, { " + ", "+", 13, 4, 3 },
      { " +8 ", "+8", 2, 5, 4 }, { " +64 ", "+64", 7, 5, 5 }, { " Max ", "Max", 13, 5, 5 },
      { " Clear ", "Clear", 2, 6, 7 }, { "  OK  ", "OK", 13, 6, 6 },
    }
    for _, b in ipairs(btns) do
      local bx, by, bw = kx + b[3], ky + b[4], b[5]
      local rect = { x1 = bx, y1 = by, x2 = bx + bw - 1, y2 = by }
      if b[2] == nil then
        -- поле значения
        fill(monitor, rect, C.bg)
        local vs = tostring(kp.value)
        text(monitor, bx + math.floor((bw - #vs) / 2), by, vs, C.brass, C.bg)
      else
        local face = C.casing
        local fg = C.ink
        if b[2] == "OK" then face = C.brass; fg = C.bg end
        fill(monitor, rect, face)
        bevel(monitor, rect, C.casingHi, C.casingLo)
        text(monitor, bx, by, b[1], fg, face)
        hit.keypad[#hit.keypad + 1] = { rect = rect, key = b[2] }
      end
    end
  end

  return hit
end

return M
