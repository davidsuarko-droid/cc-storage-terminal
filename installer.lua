-- cc-storage-terminal installer. Run: wget run <url>
-- СГЕНЕРИРОВАНО scripts/gen-installer.lua — не править вручную.
-- Пишет все модули плоско в корень компа.
local F = {}
F["addresses.lua"] = [=[
-- Список адресов доставки пакетной сети Create.
local M = {}

function M.parse(text)
  local out = {}
  for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
    local trimmed = line:gsub("%s+", "")
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      out[#out + 1] = trimmed
    end
  end
  if #out == 0 then return { "Main", "Core" } end
  return out
end

function M.default(list) return list[1] end

return M
]=]
F["classify.lua"] = [=[
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
]=]
F["config.lua"] = [=[
-- Конфиг терминала. Стороны nil = авто-детект периферии по типу.
local config = {
  REFRESH      = 2,   -- секунды между обновлениями стока
  TICKER_SIDE  = nil, -- напр. "back" чтобы форсить сторону тикера
  MONITOR_SIDE = nil, -- напр. "left" чтобы форсить сторону монитора
  MODEM_SIDE   = nil, -- напр. "top" чтобы форсить сторону модема (rednet)
}
return config
]=]
F["names.lua"] = [=[
-- Карта кастомных имён id->ярлык + fallback-логика.
local M = {}
local map = {}

function M.reset() map = {} end

function M.parse(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      local id, label = trimmed:match("^(.-)%s*=%s*(.+)$")
      if id and label then out[id] = label end
    end
  end
  return out
end

function M.load(reader)
  local text = reader("names.cfg")
  map = text and M.parse(text) or {}
end

function M.pretty(id)
  local name = id:match(":(.+)$") or id
  name = name:gsub("_", " ")
  return (name:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b:lower() end))
end

function M.label(id, displayName)
  if map[id] then return map[id] end
  if displayName and displayName ~= "" then return displayName end
  return M.pretty(id)
end

return M
]=]
F["net.lua"] = [=[
-- Сетевой протокол server<->pocket поверх rednet. Чистые строители сообщений
-- (тестируемы) + тонкие I/O-обёртки над rednet/peripheral.
local M = {}

M.PROTO = "ccstore"

-- === чистые строители/валидаторы сообщений ===

function M.reqStock()
  return { t = "stock" }
end

-- ответ на запрос стока: список товаров + адреса доставки
function M.respStock(items, addresses)
  return { t = "stock", items = items or {}, addresses = addresses or {} }
end

function M.reqOrder(id, qty, address)
  return { t = "order", id = id, qty = qty, address = address }
end

function M.respOrder(got)
  return { t = "order", got = got or 0 }
end

-- тип сообщения или nil, если это не наш кадр
function M.kind(msg)
  if type(msg) ~= "table" then return nil end
  return msg.t
end

-- === I/O: открыть rednet на первом модеме (или заданной стороне) ===
-- Возвращает сторону или nil, если модема нет (вызывающий решает, фатально ли это).
function M.open(side)
  if side then
    rednet.open(side)
    return side
  end
  for _, s in ipairs(rs.getSides()) do
    if peripheral.getType(s) == "modem" then
      rednet.open(s)
      return s
    end
  end
  return nil
end

return M
]=]
F["order.lua"] = [=[
-- Размещение заказа на адрес пакетной сети.
local M = {}

function M.place(ticker, id, qty, address)
  return ticker.requestFiltered(address, { name = id, _requestCount = qty })
end

return M
]=]
F["peripherals.lua"] = [=[
-- Поиск тикера и монитора по типу (со страховкой override через сторону).
local M = {}

function M.find(config)
  local ticker = config.TICKER_SIDE and peripheral.wrap(config.TICKER_SIDE)
    or peripheral.find("Create_StockTicker")
  if not ticker then
    error("No Create_StockTicker. Attach a Stock Ticker to the computer.", 0)
  end

  local monitor = config.MONITOR_SIDE and peripheral.wrap(config.MONITOR_SIDE)
    or peripheral.find("monitor")
    or peripheral.find("monitor_advanced")
  if not monitor then
    error("No monitor. Attach an Advanced Monitor.", 0)
  end

  return ticker, monitor
end

return M
]=]
F["pocket.lua"] = [=[
-- Покет-клиент: портативный advanced-компьютер. Своего тикера нет —
-- тянет сток у сервера по rednet, рисует на экране term, заказ мышью
-- (ЛКМ=стак, ПКМ=1шт, колесо над плиткой=±шаг, иначе листает).
local config   = require("config")
local stock    = require("stock")
local ui_logic = require("ui_logic")
local render   = require("render_text")
local net      = require("net")

if not net.open(config.MODEM_SIDE) then
  error("No modem. Equip a Wireless/Ender Modem on the pocket computer.", 0)
end
render.applyPalette(term)

local model = {
  items = {}, groups = { "All" }, group = "All",
  query = "", searchFocus = false, scroll = 0,
  addresses = {}, addrIdx = 1, address = nil,
  toast = nil, keypad = nil,
  basket = ui_logic.basketNew(), step = 1,
}
local allItems = {}
local hit = {}

local function rebuild()
  local list = ui_logic.byGroup(allItems, model.group)
  model.items = ui_logic.filter(list, model.query)
  model.scroll = 0
end

local function gridPerPage()
  local w, h = term.getSize()
  local L = ui_logic.layout(w, h)
  return ui_logic.gridDims(L.grid, 12, 6, 1).perPage
end

local function redraw()
  hit = render.draw(term, model)
end

-- запрос стока у сервера (broadcast, первый ответ)
local function pull()
  rednet.broadcast(net.reqStock(), net.PROTO)
  local _, msg = rednet.receive(net.PROTO, 2)
  if net.kind(msg) == "stock" then
    allItems = msg.items
    model.groups = stock.groups(allItems)
    model.addresses = msg.addresses
    if not model.address then
      model.address = model.addresses[1]
    end
    rebuild()
    model.toast = nil
  else
    model.toast = "No server"
  end
end

-- послать один заказ серверу, вернуть выданное кол-во
local function sendOrder(id, qty, addr)
  rednet.broadcast(net.reqOrder(id, qty, addr), net.PROTO)
  local _, msg = rednet.receive(net.PROTO, 2)
  if net.kind(msg) == "order" then return msg.got or 0 end
  return 0
end

local function confirmCart()
  local lines, units = 0, 0
  for _, b in ipairs(ui_logic.basketList(model.basket)) do
    local got = sendOrder(b.entry.id, b.qty, model.address)
    if got > 0 then lines = lines + 1; units = units + got end
  end
  model.basket = ui_logic.basketNew()
  model.toast = lines > 0
    and ("Sent " .. units .. " units (" .. lines .. " items)")
    or "Out of stock"
end

local function tileAt(x, y)
  for _, it in ipairs(hit.tiles or {}) do
    if ui_logic.inside(it.rect, x, y) then return it end
  end
  return nil
end

-- ЛКМ=стак(64), ПКМ=1шт, прочие зоны = действие
local function handleClick(button, x, y)
  model.pressed = nil
  if ui_logic.inside(hit.search, x, y) then model.searchFocus = true; return end
  model.searchFocus = false
  if ui_logic.inside(hit.addr, x, y) then
    if #model.addresses > 0 then
      model.addrIdx = (model.addrIdx % #model.addresses) + 1
      model.address = model.addresses[model.addrIdx]
    end
    return
  end
  if hit.up and ui_logic.inside(hit.up, x, y) then model.scroll = model.scroll - gridPerPage(); return end
  if hit.down and ui_logic.inside(hit.down, x, y) then model.scroll = model.scroll + gridPerPage(); return end
  if hit.step and ui_logic.inside(hit.step, x, y) then model.step = ui_logic.nextStep(model.step); return end
  if hit.clear and ui_logic.inside(hit.clear, x, y) then
    model.basket = ui_logic.basketNew(); model.toast = "Cart cleared"; return
  end
  if hit.confirm and ui_logic.inside(hit.confirm, x, y) then confirmCart(); return end
  for _, c in ipairs(hit.chips or {}) do
    if ui_logic.inside(c.rect, x, y) then model.group = c.group; rebuild(); return end
  end
  local it = tileAt(x, y)
  if it then
    local delta = (button == 1 and 64) or (button == 2 and 1) or model.step
    ui_logic.basketAdd(model.basket, it.entry, delta)
    model.pressed = it.entry.id
  end
end

-- колесо над плиткой = ±шаг этой плитке; иначе листает грид (dir: -1 вверх, 1 вниз)
local function handleScroll(dir, x, y)
  local it = tileAt(x, y)
  if it then
    ui_logic.basketAdd(model.basket, it.entry, dir < 0 and model.step or -model.step)
    model.pressed = it.entry.id
  else
    model.scroll = model.scroll + (dir > 0 and gridPerPage() or -gridPerPage())
  end
end

pull()
redraw()
local timer = os.startTimer(config.REFRESH)
while true do
  local ev = { os.pullEvent() }
  local n = ev[1]
  if n == "timer" and ev[2] == timer then
    pull(); redraw(); timer = os.startTimer(config.REFRESH)
  elseif n == "mouse_click" then
    handleClick(ev[2], ev[3], ev[4]); redraw()
  elseif n == "mouse_scroll" then
    handleScroll(ev[2], ev[3], ev[4]); redraw()
  elseif n == "char" and model.searchFocus then
    model.query = model.query .. ev[2]; rebuild(); redraw()
  elseif n == "key" and model.searchFocus then
    if ev[2] == keys.backspace then
      model.query = model.query:sub(1, -2); rebuild(); redraw()
    elseif ev[2] == keys.enter then
      model.searchFocus = false; redraw()
    end
  end
end
]=]
F["render_gpu.lua"] = [=[
-- GPU-рендер (Tom's Peripherals). Пиксельные плитки, крупный текст, реальные
-- иконки (Phase 3). Полноцвет ARGB — палитру не перекраиваем. Chrome — English
-- ASCII. Возвращает хит-зоны в пикселях. Тач: тап=+step, sneak+тап=+16.
local ui_logic = require("ui_logic")
local M = {}

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

-- GPU полноцветный — перекрашивать палитру не нужно.
function M.applyPalette(_surface) end

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
local function bevel(g, r, face, hi, lo)
  rect(g, r, face)
  g.line(r.x1, r.y1, r.x2, r.y1, hi)
  g.line(r.x1, r.y1, r.x1, r.y2, hi)
  g.line(r.x1, r.y2, r.x2, r.y2, lo)
  g.line(r.x2, r.y1, r.x2, r.y2, lo)
end

local function trunc(s, max)
  if max <= 0 then return "" end
  if #s <= max then return s end
  if max <= 2 then return s:sub(1, max) end
  return s:sub(1, max - 2) .. ".."
end

-- Пиксель-глиф категории: 32x32 блок цвета категории с рамкой (заглушка вместо
-- реальной текстуры; Phase 3 заменит на drawImage).
local function catIcon(g, x, y, group)
  local col = CAT[group] or C.muted
  g.filledRectangle(x, y, 32, 32, col)
  g.rectangle(x, y, 32, 32, C.ink)
  g.filledRectangle(x + 12, y + 12, 8, 8, C.ink) -- метка-«ядро»
end

-- одна плитка предмета (иконка + сток + полное имя + бейдж корзины).
local function drawTile(g, t, model)
  local r, e = t.rect, t.entry
  local inCart = ui_logic.basketQty(model.basket, e.id)
  local pressed = model.pressed == e.id
  local face = pressed and C.casingHi or C.panel
  local frame = inCart > 0 and C.brass or C.casingLo
  bevel(g, r, face, frame, frame)
  catIcon(g, r.x1 + 4, r.y1 + 4, e.group)
  -- сток справа сверху
  g.drawText(r.x1 + 40, r.y1 + 6, "x" .. e.count, C.muted, nil, 1)
  -- бейдж корзины
  if inCart > 0 then
    g.drawText(r.x1 + 40, r.y1 + 18, "+" .. inCart, C.brass, nil, 1)
  end
  -- полное имя в 2 строки снизу
  local lines = ui_logic.wrap2(e.display, 11)
  g.drawText(r.x1 + 4, r.y2 - 18, lines[1], C.text, nil, 1)
  if lines[2] ~= "" then g.drawText(r.x1 + 4, r.y2 - 8, lines[2], C.text, nil, 1) end
end

-- кнопка справа налево; возвращает rect и сдвигает rx.
local function btnRow(g, state, label, face, fg)
  local pad = 8
  local wbtn = #label * 6 + pad * 2
  local x1 = state.rx - wbtn + 1
  local r = { x1 = x1, y1 = state.y1, x2 = state.rx, y2 = state.y2 }
  bevel(g, r, face, C.casingHi, C.casingLo)
  g.drawText(x1 + pad, state.y1 + 6, label, fg, nil, 1)
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
  g.drawText(P.title.x1 + 6, P.title.y1 + 4, "STORAGE", C.brass, nil, 1)
  rect(g, P.addr, C.brass)
  g.drawText(P.addr.x1 + 6, P.addr.y1 + 4, trunc("Deliver: " .. (model.address or "?") .. " >", 22), C.bg, nil, 1)
  hit.addr = P.addr

  -- search
  local focused = model.searchFocus
  rect(g, P.search, focused and C.brass or C.panel)
  local q = (model.query ~= "" and model.query) or "type to filter..."
  g.drawText(P.search.x1 + 6, P.search.y1 + 3, "Search: " .. q, focused and C.bg or C.text, nil, 1)
  g.drawText(P.search.x2 - 80, P.search.y1 + 3, #model.items .. " items", focused and C.bg or C.muted, nil, 1)
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
    g.drawText(cx + 6, P.chips.y1 + 4, c.label, active and C.bg or C.ink, nil, 1)
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
    g.drawText(P.up.x1 + 6, P.up.y1 + 8, "^", C.bg, nil, 2)
    hit.up = P.up
  end
  if pg.hasDown then
    bevel(g, P.down, C.brass, C.brassHi, C.casingLo)
    g.drawText(P.down.x1 + 6, P.down.y1 + 8, "v", C.bg, nil, 2)
    hit.down = P.down
  end

  -- панель корзины (слева) с собственной прокруткой
  local totals = ui_logic.basketTotals(model.basket)
  bevel(g, P.cart, C.panel, C.casingHi, C.casingLo)
  g.drawText(P.cart.x1 + 6, P.cart.y1 + 4, trunc("CART " .. totals.units .. "u", 16), C.brass, nil, 1)
  local list = ui_logic.basketList(model.basket)
  local rowH = 12
  local listTop = P.cart.y1 + 22
  local listRows = math.max(1, math.floor((P.cart.y2 - 20 - listTop) / rowH))
  local cpg = ui_logic.page(list, model.cartScroll or 0, listRows)
  model.cartScroll = cpg.scroll
  if #list == 0 then
    g.drawText(P.cart.x1 + 6, listTop, "empty - tap tiles", C.muted, nil, 1)
  else
    for i, b in ipairs(cpg.slice) do
      local y = listTop + (i - 1) * rowH
      g.drawText(P.cart.x1 + 6, y, trunc(b.qty .. "x " .. b.entry.display, 18), C.text, nil, 1)
    end
    if cpg.hasUp then
      bevel(g, P.cartUp, C.casing, C.casingHi, C.casingLo)
      g.drawText(P.cartUp.x1 + 6, P.cartUp.y1 + 4, "^", C.ink, nil, 1)
      hit.cartUp = P.cartUp
    end
    if cpg.hasDown then
      bevel(g, P.cartDown, C.casing, C.casingHi, C.casingLo)
      g.drawText(P.cartDown.x1 + 6, P.cartDown.y1 + 4, "v", C.ink, nil, 1)
      hit.cartDown = P.cartDown
    end
  end

  -- статус-строка
  rect(g, P.status, C.bg)
  local hint = model.toast or "Tap +" .. (model.step or 32) .. "  |  Sneak+tap +16  |  Step cycles"
  g.drawText(P.status.x1 + 4, P.status.y1 + 3, trunc(hint, 60), model.toast and C.brassHi or C.muted, nil, 1)

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
]=]
F["render_text.lua"] = [=[
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
  local inCart = ui_logic.basketQty(model.basket, e.id)
  local catColor = CAT[e.group] or C.muted
  -- в корзине → латунная рамка (выделение), иначе цвет категории
  local frame = (pressed or inCart > 0) and C.brass or catColor
  local face  = pressed and C.brassHi or C.casing
  -- рамка = заливка всего прямоугольника цветом категории
  fill(mon, r, frame)
  -- внутренняя грань — корпус
  fill(mon, { x1 = r.x1 + 1, y1 = r.y1 + 1, x2 = r.x2 - 1, y2 = r.y2 - 1 }, face)
  -- спрайт категории 2x2 в левом-верхнем углу контента
  sprites.draw(mon, r.x1 + 1, r.y1 + 1, e.group, catColor, face)
  -- счётчик стока xN справа сверху
  local cstr = "x" .. e.count
  local cx = r.x2 - 1 - #cstr + 1
  if cx > r.x1 + 3 then text(mon, cx, r.y1 + 1, cstr, C.ink, face) end
  -- бейдж корзины (+N) справа, вторая строка
  if inCart > 0 then
    local bstr = "+" .. inCart
    local bx = r.x2 - 1 - #bstr + 1
    if bx > r.x1 + 3 then text(mon, bx, r.y1 + 2, bstr, C.brass, face) end
  end
  -- имя в 2 строки снизу
  local innerW = (r.x2 - 1) - (r.x1 + 1) + 1
  local lines = ui_logic.wrap2(e.display, innerW)
  text(mon, r.x1 + 1, r.y2 - 2, lines[1], C.ink, face)
  if lines[2] ~= "" then text(mon, r.x1 + 1, r.y2 - 1, lines[2], C.ink, face) end
end

function M.draw(monitor, model)
  if monitor.setTextScale then monitor.setTextScale(0.5) end -- монитор: мельче; term: нет
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

  local totals = ui_logic.basketTotals(model.basket)

  -- панель корзины (низ-слева): заголовок + строки "Qx Name", последняя "+K more"
  fill(monitor, L.cart, C.casing)
  bevel(monitor, L.cart, C.casingHi, C.casingLo)
  local cw = L.cart.x2 - L.cart.x1 + 1
  local chead = "CART " .. totals.units .. "u"
  text(monitor, L.cart.x1 + 1, L.cart.y1, trunc(chead, cw - 2), C.brass, C.casing)
  local listRows = L.cart.y2 - (L.cart.y1 + 1) + 1   -- сколько строк под список
  local lines = ui_logic.basketList(model.basket)
  if #lines == 0 then
    text(monitor, L.cart.x1 + 1, L.cart.y1 + 1, trunc("empty - tap tiles", cw - 2), C.muted, C.casing)
  else
    for i = 1, listRows do
      local y = L.cart.y1 + i
      if i == listRows and #lines > listRows then
        text(monitor, L.cart.x1 + 1, y, "+" .. (#lines - listRows + 1) .. " more", C.muted, C.casing)
      elseif lines[i] then
        local b = lines[i]
        text(monitor, L.cart.x1 + 1, y, trunc(b.qty .. "x " .. b.entry.display, cw - 2), C.ink, C.casing)
      end
    end
  end

  -- скролл-строка (правая колонка): page X/Y + стрелки
  fill(monitor, L.scroll, C.bg)
  local total = #model.items
  local page = math.floor((model.scroll or 0) / dims.perPage) + 1
  local pages = math.max(1, math.ceil(total / dims.perPage))
  text(monitor, L.scroll.x1, L.scroll.y1, trunc("page " .. page .. "/" .. pages, L.up.x1 - L.scroll.x1 - 1), C.muted, C.bg)
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

  -- ряд кнопок (правая колонка): Confirm / Clear / Step справа налево
  fill(monitor, L.btns, C.bg)
  local by2 = L.btns.y1
  local rx = w
  local function btnR(label, bg, fg)
    local x1 = rx - #label + 1
    fill(monitor, { x1 = x1, y1 = by2, x2 = rx, y2 = by2 }, bg)
    text(monitor, x1, by2, label, fg, bg)
    local rect = { x1 = x1, y1 = by2, x2 = rx, y2 = by2 }
    rx = x1 - 1
    return rect
  end
  hit.step = btnR(" Step:" .. (model.step or 1) .. " ", C.casing, C.ink)
  if totals.lines > 0 then
    hit.clear = btnR(" Clear ", C.copper, C.text)
    hit.confirm = btnR(" Confirm ", C.brass, C.bg)
  end

  -- статус-строка (правая колонка): тост или подсказка
  fill(monitor, L.status, C.bg)
  local hint = model.toast or "Tap = +Step  |  Step 1/8/64  |  chip filters"
  text(monitor, L.status.x1, L.status.y1, trunc(hint, w - L.status.x1),
    model.toast and C.brassHi or C.muted, C.bg)

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

-- === Backend-интерфейс (общий с render_gpu) ===
M.defaultStep = 1

-- Цикл шага накопления для тач-монитора: 1 → 8 → 64 → 1.
function M.nextStep(step)
  return ui_logic.nextStep(step)
end

-- Сколько плиток на странице при текущем размере поверхности (символы).
function M.perPage(surface)
  local w, h = surface.getSize()
  local L = ui_logic.layout(w, h)
  return ui_logic.gridDims(L.grid, 12, 6, 1).perPage
end

return M
]=]
F["server.lua"] = [=[
-- Сервер: стационарный компьютер. Владеет тикером, монитором, модемом.
-- Рисует стенной монитор (тач-заказ) И раздаёт сток/заказы покет-клиентам по rednet.
local config      = require("config")
local names       = require("names")
local addresses   = require("addresses")
local stock       = require("stock")
local ui_logic    = require("ui_logic")
local order       = require("order")
local peripherals = require("peripherals")
local render_text = require("render_text")
local net         = require("net")

local function readFile(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local data = h.readAll()
  h.close()
  return data
end

local ticker, monitor = peripherals.find(config)
-- Бэкенд рендера: есть Tom's GPU → пиксельный render_gpu на его мониторе;
-- нет → символьный render_text на CC-мониторе (старое поведение).
local backend, surface
local gpu = peripheral.find("tm_gpu")
if gpu then
  backend = require("render_gpu")
  surface = gpu
else
  backend = render_text
  surface = monitor
end
backend.applyPalette(surface)
local modemSide = net.open(config.MODEM_SIDE) -- nil = модема нет, работаем как монитор без раздачи
names.load(readFile)
local addrList = addresses.parse(readFile("addresses.cfg"))

local model = {
  items = {}, groups = { "All" }, group = "All",
  query = "", searchFocus = false, scroll = 0,
  addresses = addrList, addrIdx = 1, address = addresses.default(addrList),
  toast = nil, keypad = nil,
  basket = ui_logic.basketNew(), step = backend.defaultStep,
}
local allItems = {}
local hit = {}

local function rebuild()
  local list = ui_logic.byGroup(allItems, model.group)
  model.items = ui_logic.filter(list, model.query)
  model.scroll = 0
end

local function gridPerPage()
  return backend.perPage(surface)
end

local function refreshStock()
  local ok, raw = pcall(function() return ticker.stock(true) end)
  if ok and raw then
    allItems = stock.normalize(raw, names)
    model.groups = stock.groups(allItems)
    rebuild()
  else
    model.toast = "No network"
  end
end

local function redraw()
  hit = backend.draw(surface, model)
end

local function refreshLoop()
  while true do
    refreshStock()
    redraw()
    os.sleep(config.REFRESH)
  end
end

local function handleTouch(x, y, sneaking)
  model.pressed = nil
  if ui_logic.inside(hit.search, x, y) then
    model.searchFocus = true
    return
  end
  model.searchFocus = false
  if ui_logic.inside(hit.addr, x, y) then
    model.addrIdx = (model.addrIdx % #model.addresses) + 1
    model.address = model.addresses[model.addrIdx]
    return
  end
  if hit.up and ui_logic.inside(hit.up, x, y) then
    model.scroll = model.scroll - gridPerPage()
    return
  end
  if hit.down and ui_logic.inside(hit.down, x, y) then
    model.scroll = model.scroll + gridPerPage()
    return
  end
  if hit.cartUp and ui_logic.inside(hit.cartUp, x, y) then
    model.cartScroll = (model.cartScroll or 0) - 1
    return
  end
  if hit.cartDown and ui_logic.inside(hit.cartDown, x, y) then
    model.cartScroll = (model.cartScroll or 0) + 1
    return
  end
  if hit.step and ui_logic.inside(hit.step, x, y) then
    model.step = backend.nextStep(model.step)
    return
  end
  if hit.clear and ui_logic.inside(hit.clear, x, y) then
    model.basket = ui_logic.basketNew()
    model.toast = "Cart cleared"
    return
  end
  if hit.confirm and ui_logic.inside(hit.confirm, x, y) then
    local lines, units = 0, 0
    for _, b in ipairs(ui_logic.basketList(model.basket)) do
      local got = order.place(ticker, b.entry.id, b.qty, model.address)
      if got > 0 then lines = lines + 1; units = units + got end
    end
    model.basket = ui_logic.basketNew()
    model.toast = lines > 0
      and ("Sent " .. units .. " units (" .. lines .. " items) -> " .. model.address)
      or "Out of stock"
    return
  end
  for _, c in ipairs(hit.chips or {}) do
    if ui_logic.inside(c.rect, x, y) then
      model.group = c.group
      rebuild()
      return
    end
  end
  for _, it in ipairs(hit.tiles or {}) do
    if ui_logic.inside(it.rect, x, y) then
      local delta = sneaking and 16 or model.step
      ui_logic.basketAdd(model.basket, it.entry, delta)
      model.pressed = it.entry.id
      return
    end
  end
end

local function inputLoop()
  while true do
    local ev = { os.pullEvent() }
    local name = ev[1]
    if name == "monitor_touch" then
      handleTouch(ev[3], ev[4])
      redraw()
    elseif name == "tm_monitor_touch" then
      handleTouch(ev[2], ev[3], ev[4]) -- (x, y, sneaking)
      redraw()
    elseif name == "char" and model.searchFocus then
      model.query = model.query .. ev[2]
      rebuild()
      redraw()
    elseif name == "key" and model.searchFocus then
      if ev[2] == keys.backspace then
        model.query = model.query:sub(1, -2)
        rebuild()
        redraw()
      elseif ev[2] == keys.enter then
        model.searchFocus = false
        redraw()
      end
    end
  end
end

-- раздача стока/заказов покет-клиентам
local function serveLoop()
  while true do
    local id, msg = rednet.receive(net.PROTO)
    local kind = net.kind(msg)
    if kind == "stock" then
      rednet.send(id, net.respStock(allItems, model.addresses), net.PROTO)
    elseif kind == "order" then
      local got = order.place(ticker, msg.id, msg.qty, msg.address)
      rednet.send(id, net.respOrder(got), net.PROTO)
    end
  end
end

refreshStock()
redraw()
if modemSide then
  parallel.waitForAll(refreshLoop, inputLoop, serveLoop)
else
  parallel.waitForAll(refreshLoop, inputLoop) -- модема нет: только локальный монитор
end
]=]
F["sprites.lua"] = [=[
-- Пиксель-спрайты категорий через сикстант-символы CC (коды 128-159).
-- 1 клетка = блок 2x3 субпикселя. Спрайт = 2x2 клетки = 4x6 пикселей, 2 цвета.
-- Чистый энкодер M.cell юнит-тестируем; M.draw — I/O (пишет на монитор).
local M = {}

-- Кодирование одной клетки. Субпиксели: TL,TR,ML,MR,BL,BR (truthy = "вкл").
-- CC: символ 128+маска рисует 5 субпикселей цветом текста, остальное — фоном.
-- 6-й (BR) опорный: если "вкл" → инверсия (рисуем 128+доп.маска, меняя fg/bg).
-- Возвращает (charByte, invert).
function M.cell(tl, tr, ml, mr, bl, br)
  local invert = br and true or false
  local bits = { tl, tr, ml, mr, bl }
  local n = 0
  local val = { 1, 2, 4, 8, 16 }
  for i = 1, 5 do
    local on = bits[i] and true or false
    if invert then on = not on end
    if on then n = n + val[i] end
  end
  return 128 + n, invert
end

-- Битмапы 4x6 ("#"/непробел = вкл). Подгоняются на глаз; логика от формы не зависит.
M.SPRITES = {
  Create = { " ## ", "####", "#  #", "#  #", "####", " ## " },  -- шестерёнка
  Redstone = { "  # ", " ###", "  # ", "  # ", "  # ", " ###" }, -- факел
  Resources = { "    ", " ## ", "####", "####", "####", "    " }, -- слиток
  Wood = { "####", "#  #", "####", "#  #", "####", "#  #" },      -- бревно
  Stone = { "    ", " ## ", "####", "####", " ## ", "    " },     -- камень
  Building = { "####", "# ##", "####", "## #", "####", "# ##" },  -- кирпич
  Other = { "####", "#  #", "# ##", "  # ", "    ", "  # " },     -- ящик/?
}

-- Рисует спрайт name в (x,y) 2x2 клетки. fg = цвет "вкл", bg = фон плитки.
function M.draw(mon, x, y, name, fg, bg)
  local sp = M.SPRITES[name] or M.SPRITES.Other
  local function on(r, c) return sp[r]:sub(c, c) ~= " " end
  for cy = 0, 1 do
    for cx = 0, 1 do
      local r0, c0 = cy * 3, cx * 2
      local ch, inv = M.cell(
        on(r0 + 1, c0 + 1), on(r0 + 1, c0 + 2),
        on(r0 + 2, c0 + 1), on(r0 + 2, c0 + 2),
        on(r0 + 3, c0 + 1), on(r0 + 3, c0 + 2))
      mon.setCursorPos(x + cx, y + cy)
      if inv then
        mon.setTextColor(bg); mon.setBackgroundColor(fg)
      else
        mon.setTextColor(fg); mon.setBackgroundColor(bg)
      end
      mon.write(string.char(ch))
    end
  end
end

return M
]=]
F["startup.lua"] = [=[
-- Точка входа. Покет-компьютер -> клиент; стационарный -> сервер (тикер+монитор).
-- Детект: глобал `pocket` существует только на покет-компьютерах.
if pocket then
  require("pocket")
else
  require("server")
end
]=]
F["stock.lua"] = [=[
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
]=]
F["ui_logic.lua"] = [=[
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
  local cartH = 4                                    -- нижний блок: корзина(3 ряда) + кнопки(1 ряд)
  local cartW = math.max(14, math.min(24, math.floor(w * 0.42)))
  local by = h - cartH + 1                           -- первая строка нижнего блока
  local rx1 = cartW + 2                              -- старт правой колонки (после корзины)
  return {
    title  = { x1 = 1,             y1 = 1,     x2 = w, y2 = 1 },
    addr   = { x1 = w - addrW + 1, y1 = 1,     x2 = w, y2 = 1 },
    search = { x1 = 1,             y1 = 2,     x2 = w, y2 = 2 },
    chips  = { x1 = 1,             y1 = 3,     x2 = w, y2 = 4 },
    grid   = { x1 = 1,             y1 = 5,     x2 = w, y2 = by - 1 },
    cart   = { x1 = 1,             y1 = by,    x2 = cartW, y2 = h - 1 },
    scroll = { x1 = rx1,           y1 = by,    x2 = w, y2 = by },
    up     = { x1 = w - 9,         y1 = by,    x2 = w - 5, y2 = by },
    down   = { x1 = w - 4,         y1 = by,    x2 = w, y2 = by },
    status = { x1 = rx1,           y1 = by + 1, x2 = w, y2 = by + 1 },
    btns   = { x1 = 1,             y1 = h,     x2 = w, y2 = h }, -- во всю ширину (узкий экран)
    cartW = cartW, cartH = cartH,
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

-- Пиксельная раскладка для GPU-монитора (Tom's Peripherals).
-- Та же структура зон, что layout, но в пикселях и с крупными плитками.
-- Слева — постоянная корзина со своей прокруткой; справа — грид; внизу — кнопки.
function M.layoutPx(w, h)
  local pad     = 4
  local titleH  = 18
  local searchH = 16
  local chipsH  = 20
  local btnH    = 22
  local statusH = 14
  local scrollW = 22                                  -- колонка стрелок грида справа
  local cartW   = math.max(96, math.floor(w * 0.30))  -- левая панель корзины
  local headY   = 1
  local searchY = headY + titleH
  local chipsY  = searchY + searchH
  local bodyTop = chipsY + chipsH + pad
  local btnY    = h - btnH + 1
  local statusY = btnY - statusH
  local bodyBot = statusY - pad
  local gridX1  = cartW + pad + 1
  local gridX2  = w - scrollW - pad
  return {
    title  = { x1 = 1,            y1 = headY,   x2 = w,           y2 = headY + titleH - 1 },
    addr   = { x1 = w - 140 + 1,  y1 = headY,   x2 = w,           y2 = headY + titleH - 1 },
    search = { x1 = 1,            y1 = searchY, x2 = w,           y2 = searchY + searchH - 1 },
    chips  = { x1 = 1,            y1 = chipsY,  x2 = w,           y2 = chipsY + chipsH - 1 },
    grid   = { x1 = gridX1,       y1 = bodyTop, x2 = gridX2,      y2 = bodyBot },
    scroll = { x1 = gridX2 + pad, y1 = bodyTop, x2 = w,           y2 = bodyBot },
    up     = { x1 = gridX2 + pad, y1 = bodyTop, x2 = w,           y2 = bodyTop + 28 },
    down   = { x1 = gridX2 + pad, y1 = bodyBot - 28, x2 = w,      y2 = bodyBot },
    cart   = { x1 = 1,            y1 = bodyTop, x2 = cartW,       y2 = bodyBot },
    cartUp   = { x1 = cartW - 24, y1 = bodyTop, x2 = cartW,       y2 = bodyTop + 18 },
    cartDown = { x1 = cartW - 24, y1 = bodyBot - 18, x2 = cartW,  y2 = bodyBot },
    cartScroll = { x1 = 1,        y1 = bodyTop + 20, x2 = cartW,  y2 = bodyBot - 20 },
    status = { x1 = 1,            y1 = statusY, x2 = w,           y2 = btnY - 1 },
    btns   = { x1 = 1,            y1 = btnY,    x2 = w,           y2 = h },
    cartW = cartW, pad = pad,
  }
end

-- Цикл шага накопления для GPU-тача: 1 → 16 → 32 → 64 → 1.
function M.nextStep4(step)
  if step == 1 then return 16
  elseif step == 16 then return 32
  elseif step == 32 then return 64
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
]=]
F["names.cfg"] = [=[
# Custom names: id=label. Edit in-game (edit names.cfg).
# WARNING: labels must be LATIN/ASCII only — CC monitor font has no Cyrillic
# (Cyrillic renders as garbage glyphs). Use English/transliteration.
# Example:
# minecraft:gold_nugget=Gold Nugget
# create:electrum_nugget=Electrum
]=]
F["addresses.cfg"] = [=[
# Адреса доставки пакетной сети Create. По одному на строку.
# Первый = адрес по умолчанию. Редактируется в игре.
Main
Core
]=]
for name, body in pairs(F) do
  if name:match("%.cfg$") and fs.exists(name) then
    print("skip "..name.." (есть)")
  else
    local h = fs.open(name, "w"); h.write(body); h.close()
    print("write "..name)
  end
end
print("Готово. Ребут или: startup")