-- GPU-рендер (Tom's Peripherals). Пиксельные плитки, крупный текст, реальные
-- иконки (Phase 3). Полноцвет ARGB — палитру не перекраиваем. Chrome — English
-- ASCII. Возвращает хит-зоны в пикселях. Тач: тап=+step, sneak+тап=+16.
local ui_logic = require("ui_logic")
local M = {}

local _icons = nil  -- модуль icons (инъекция через M.useIcons); nil = только глифы
function M.useIcons(mod) _icons = mod end

-- Стимпанк-палитра как ARGB 0xAARRGGBB.
local C = {
  bg       = 0xFF2A2925, -- тёмный андезит
  panel    = 0xFF3A3833, -- панель
  casing   = 0xFF8F8F86, -- андезит-корпус
  casingHi = 0xFFC2C2B6, -- светлый андезит (bevel)
  casingLo = 0xFF5A5A52, -- тёмный ридж
  text     = 0xFFE8DEC8, -- парчмент
  ink      = 0xFF1E1C18, -- near-black на светлом
  muted    = 0xFF9A9486, -- приглушённый
  brass    = 0xFFC8A24A, -- латунь — акцент
  brassHi  = 0xFFE3C77A, -- светлая латунь
  copper   = 0xFFB5512A, -- медь — danger/X
  transp   = 0x00000000, -- прозрачный bg для drawText (Tom's GPU не глотает nil)
}

-- Цвет иконки-категории (пиксель-глиф, пока нет реальной текстуры).
local CAT = {
  Create = 0xFFC8A24A, Redstone = 0xFFB5512A, Resources = 0xFF6E90B0,
  Wood = 0xFF7A5A38, Stone = 0xFF7E8A86, Building = 0xFFB5663B,
  Other = 0xFF6B6458, All = 0xFF8F8F86,
}
M._C = C
M._CAT = CAT

-- размеры плитки в пикселях (подбираются in-game, см. TODO в spec)
local TILE_W, TILE_H, GAP = 56, 44, 4

M.defaultStep = 32

function M.nextStep(step)
  return ui_logic.nextStep4(step)
end

-- GPU полноцветный — перекрашивать палитру не нужно. Но раз на старте надо
-- вызвать refreshSize(): детектит подключённые блоки Tom's Monitor и аллоцирует
-- буфер под их реальный пиксельный размер. Без него getSize() возвращает фантом,
-- layout считается под чужой размер, и рисование уходит за экран ("Out of boundary").
function M.applyPalette(surface)
  if surface and surface.refreshSize then surface.refreshSize() end
end

function M.perPage(surface)
  local w, h = surface.getSize()
  local P = ui_logic.layoutPx(w, h)
  return ui_logic.gridDims(P.grid, TILE_W, TILE_H, GAP).perPage
end

-- ===== Низкоуровневые помощники рисования =====
local function rect(g, r, color)
  g.filledRectangle(r.x1, r.y1, r.x2 - r.x1 + 1, r.y2 - r.y1 + 1, color)
end

-- beveled-панель: заливка + светлый верх/лево, тёмный низ/право (объём корпуса).
-- Рёбра — 1px-полоски filledRectangle (дёшево и точно для прямых граней).
local function bevel(g, r, face, hi, lo)
  rect(g, r, face)
  local w = r.x2 - r.x1 + 1
  local h = r.y2 - r.y1 + 1
  g.filledRectangle(r.x1, r.y1, w, 1, hi) -- верх
  g.filledRectangle(r.x1, r.y1, 1, h, hi) -- лево
  g.filledRectangle(r.x1, r.y2, w, 1, lo) -- низ
  g.filledRectangle(r.x2, r.y1, 1, h, lo) -- право
end

local function trunc(s, max)
  if max <= 0 then return "" end
  if #s <= max then return s end
  if max <= 2 then return s:sub(1, max) end
  return s:sub(1, max - 2) .. ".."
end

-- иконка предмета: реальная текстура (drawImage) если есть, иначе глиф категории.
local function drawIcon(g, x, y, e)
  if _icons then
    local ref = _icons.get(e.id)
    if ref then g.drawImage(x, y, ref); return end
  end
  local col = CAT[e.group] or C.muted
  g.filledRectangle(x, y, 32, 32, col)
  g.rectangle(x, y, 32, 32, C.ink)
  g.filledRectangle(x + 12, y + 12, 8, 8, C.ink)
end

-- одна плитка предмета (иконка + сток + полное имя + бейдж корзины).
local function drawTile(g, t, model)
  local r, e = t.rect, t.entry
  local inCart = ui_logic.basketQty(model.basket, e.id)
  local pressed = model.pressed == e.id
  local face = pressed and C.casingHi or C.panel
  local frame = inCart > 0 and C.brass or C.casingLo
  bevel(g, r, face, frame, frame)
  drawIcon(g, r.x1 + 4, r.y1 + 4, e)
  -- сток справа сверху
  g.drawText(r.x1 + 40, r.y1 + 6, "x" .. e.count, C.muted, C.transp, 1)
  -- бейдж корзины
  if inCart > 0 then
    g.drawText(r.x1 + 40, r.y1 + 18, "+" .. inCart, C.brass, C.transp, 1)
  end
  -- полное имя в 2 строки снизу
  local lines = ui_logic.wrap2(e.display, 11)
  g.drawText(r.x1 + 4, r.y2 - 18, lines[1], C.text, C.transp, 1)
  if lines[2] ~= "" then g.drawText(r.x1 + 4, r.y2 - 8, lines[2], C.text, C.transp, 1) end
end

-- кнопка справа налево; возвращает rect и сдвигает rx.
local function btnRow(g, state, label, face, fg)
  local pad = 8
  local wbtn = #label * 6 + pad * 2
  local x1 = state.rx - wbtn + 1
  local r = { x1 = x1, y1 = state.y1, x2 = state.rx, y2 = state.y2 }
  bevel(g, r, face, C.casingHi, C.casingLo)
  g.drawText(x1 + pad, state.y1 + 6, label, fg, C.transp, 1)
  state.rx = x1 - state.pad
  return r
end

function M.draw(surface, model)
  local g = surface
  local w, h = g.getSize()
  local P = ui_logic.layoutPx(w, h)
  g.filledRectangle(1, 1, w, h, C.bg)
  local hit = { tiles = {}, chips = {} }

  -- title: STORAGE + адрес справа (латунь)
  bevel(g, P.title, C.panel, C.casingHi, C.casingLo)
  g.drawText(P.title.x1 + 6, P.title.y1 + 4, "STORAGE", C.brass, C.transp, 1)
  rect(g, P.addr, C.brass)
  g.drawText(P.addr.x1 + 6, P.addr.y1 + 4, trunc("Deliver: " .. (model.address or "?") .. " >", 22), C.bg, C.transp, 1)
  hit.addr = P.addr

  -- search
  local focused = model.searchFocus
  rect(g, P.search, focused and C.brass or C.panel)
  local q = (model.query ~= "" and model.query) or "type to filter..."
  g.drawText(P.search.x1 + 6, P.search.y1 + 3, "Search: " .. q, focused and C.bg or C.text, C.transp, 1)
  g.drawText(P.search.x2 - 80, P.search.y1 + 3, #model.items .. " items", focused and C.bg or C.muted, C.transp, 1)
  hit.search = P.search

  -- чипы категорий
  rect(g, P.chips, C.bg)
  local chips = ui_logic.chips(model.groups, P.chips.x1 + 2, P.chips.y1, w, 1)
  local cx = P.chips.x1 + 4
  for _, c in ipairs(chips) do
    local active = (c.group == model.group)
    local wlab = #c.label * 6 + 12
    local r = { x1 = cx, y1 = P.chips.y1, x2 = cx + wlab - 1, y2 = P.chips.y2 }
    bevel(g, r, active and C.brass or C.casing, active and C.brassHi or C.casingHi, C.casingLo)
    g.drawText(cx + 6, P.chips.y1 + 4, c.label, active and C.bg or C.ink, C.transp, 1)
    hit.chips[#hit.chips + 1] = { rect = r, group = c.group }
    cx = cx + wlab + 4
    if cx > w then break end
  end

  -- грид плиток
  local dims = ui_logic.gridDims(P.grid, TILE_W, TILE_H, GAP)
  local step = { x = TILE_W + GAP, y = TILE_H + GAP }
  local pg = ui_logic.page(model.items, model.scroll or 0, dims.perPage)
  model.scroll = pg.scroll
  for i, e in ipairs(pg.slice) do
    local idx = i - 1
    local col = idx % dims.cols
    local row = math.floor(idx / dims.cols)
    local x1 = P.grid.x1 + col * step.x
    local y1 = P.grid.y1 + row * step.y
    local r = { x1 = x1, y1 = y1, x2 = x1 + TILE_W - 1, y2 = y1 + TILE_H - 1 }
    local t = { entry = e, rect = r }
    drawTile(g, t, model)
    hit.tiles[#hit.tiles + 1] = { rect = r, entry = e }
  end

  -- scroll-колонка: стрелки грида
  rect(g, P.scroll, C.bg)
  if pg.hasUp then
    bevel(g, P.up, C.brass, C.brassHi, C.casingLo)
    g.drawText(P.up.x1 + 6, P.up.y1 + 8, "^", C.bg, C.transp, 2)
    hit.up = P.up
  end
  if pg.hasDown then
    bevel(g, P.down, C.brass, C.brassHi, C.casingLo)
    g.drawText(P.down.x1 + 6, P.down.y1 + 8, "v", C.bg, C.transp, 2)
    hit.down = P.down
  end

  -- панель корзины (слева) с собственной прокруткой
  local totals = ui_logic.basketTotals(model.basket)
  bevel(g, P.cart, C.panel, C.casingHi, C.casingLo)
  g.drawText(P.cart.x1 + 6, P.cart.y1 + 4, trunc("CART " .. totals.units .. "u", 16), C.brass, C.transp, 1)
  local list = ui_logic.basketList(model.basket)
  local rowH = 12
  local listTop = P.cart.y1 + 22
  local listRows = math.max(1, math.floor((P.cart.y2 - 20 - listTop) / rowH))
  local cpg = ui_logic.page(list, model.cartScroll or 0, listRows)
  model.cartScroll = cpg.scroll
  if #list == 0 then
    g.drawText(P.cart.x1 + 6, listTop, "empty - tap tiles", C.muted, C.transp, 1)
  else
    for i, b in ipairs(cpg.slice) do
      local y = listTop + (i - 1) * rowH
      g.drawText(P.cart.x1 + 6, y, trunc(b.qty .. "x " .. b.entry.display, 18), C.text, C.transp, 1)
    end
    if cpg.hasUp then
      bevel(g, P.cartUp, C.casing, C.casingHi, C.casingLo)
      g.drawText(P.cartUp.x1 + 6, P.cartUp.y1 + 4, "^", C.ink, C.transp, 1)
      hit.cartUp = P.cartUp
    end
    if cpg.hasDown then
      bevel(g, P.cartDown, C.casing, C.casingHi, C.casingLo)
      g.drawText(P.cartDown.x1 + 6, P.cartDown.y1 + 4, "v", C.ink, C.transp, 1)
      hit.cartDown = P.cartDown
    end
  end

  -- статус-строка
  rect(g, P.status, C.bg)
  local hint = model.toast or "Tap +" .. (model.step or 32) .. "  |  Sneak+tap +16  |  Step cycles"
  g.drawText(P.status.x1 + 4, P.status.y1 + 3, trunc(hint, 60), model.toast and C.brassHi or C.muted, C.transp, 1)

  -- ряд кнопок (низ): Step / Clear / Confirm справа налево
  rect(g, P.btns, C.bg)
  local state = { rx = w - 4, y1 = P.btns.y1 + 2, y2 = P.btns.y2 - 2, pad = 6 }
  hit.step = btnRow(g, state, "Step:" .. (model.step or 32), C.casing, C.ink)
  if totals.lines > 0 then
    hit.clear = btnRow(g, state, "Clear", C.copper, C.text)
    hit.confirm = btnRow(g, state, "Confirm", C.brass, C.bg)
  end

  if g.sync then g.sync() end
  return hit
end

return M
