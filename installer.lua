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
    error("Не найден Create_StockTicker. Подключи Stock Ticker к компьютеру.", 0)
  end

  local monitor = config.MONITOR_SIDE and peripheral.wrap(config.MONITOR_SIDE)
    or peripheral.find("monitor")
    or peripheral.find("monitor_advanced")
  if not monitor then
    error("Не найден монитор. Подключи Advanced Monitor.", 0)
  end

  return ticker, monitor
end

return M
]=]
F["render.lua"] = [=[
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

-- одна плитка предмета
local function drawTile(mon, t, model)
  local r = t.rect
  local e = t.entry
  local pressed = model.pressed == e.id
  local face = pressed and C.brassHi or C.casing
  fill(mon, r, face)
  if pressed then
    bevel(mon, r, C.brass, C.brass)
  else
    bevel(mon, r, C.casingHi, C.casingLo)
  end
  -- спрайт категории 2x2 в левом-верхнем углу контента
  local catColor = CAT[e.group] or C.muted
  sprites.draw(mon, r.x1 + 1, r.y1 + 1, e.group, catColor, face)
  -- счётчик xN справа сверху
  local cstr = "x" .. e.count
  local cx = r.x2 - 1 - #cstr + 1
  if cx > r.x1 + 3 then text(mon, cx, r.y1 + 1, cstr, C.ink, face) end
  -- имя/id снизу
  local nameMax = (r.x2 - 1) - (r.x1 + 1) + 1
  text(mon, r.x1 + 1, r.y2 - 1, trunc(e.display, nameMax), C.ink, face)
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

  -- чипы категорий (горизонталь)
  fill(monitor, L.chips, C.bg)
  local chips = ui_logic.chips(model.groups, L.chips.x1, L.chips.y1, w)
  for _, c in ipairs(chips) do
    local active = (c.group == model.group)
    local cbg = active and C.brass or C.casing
    local cfg = active and C.bg or C.text
    fill(monitor, c.rect, cbg)
    text(monitor, c.rect.x1, c.rect.y1, c.label, cfg, cbg)
    hit.chips[#hit.chips + 1] = { rect = c.rect, group = c.group }
  end

  -- грид плиток
  local dims = ui_logic.gridDims(L.grid, 9, 5, 1)
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
-- Storage Terminal — точка входа. Два цикла: refresh + input.
local config      = require("config")
local names       = require("names")
local addresses   = require("addresses")
local stock       = require("stock")
local ui_logic    = require("ui_logic")
local order       = require("order")
local peripherals = require("peripherals")
local render      = require("render")

-- чтение файла как строки (или nil)
local function readFile(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local data = h.readAll()
  h.close()
  return data
end

local ticker, monitor = peripherals.find(config)
render.applyPalette(monitor)
names.load(readFile)
local addrList = addresses.parse(readFile("addresses.cfg"))

local model = {
  items = {}, groups = { "All" }, group = "All",
  query = "", searchFocus = false, scroll = 0,
  addresses = addrList, addrIdx = 1, address = addresses.default(addrList),
  toast = nil, keypad = nil,
}
local allItems = {}
local hit = {}

local function rebuild()
  local list = ui_logic.byGroup(allItems, model.group)
  model.items = ui_logic.filter(list, model.query)
  model.scroll = 0
end

-- сколько плиток на странице (для скролла на страницу)
local function gridPerPage()
  local w, h = monitor.getSize()
  local L = ui_logic.layout(w, h)
  return ui_logic.gridDims(L.grid, 9, 5, 1).perPage
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
  hit = render.draw(monitor, model)
end

-- цикл обновления стока
local function refreshLoop()
  while true do
    refreshStock()
    redraw()
    os.sleep(config.REFRESH)
  end
end

local function handleTouch(x, y)
  model.pressed = nil
  -- кейпад имеет приоритет (оверлей)
  if model.keypad then
    for _, b in ipairs(hit.keypad or {}) do
      if ui_logic.inside(b.rect, x, y) then
        if b.key == "X" then
          model.keypad = nil
        elseif b.key == "OK" then
          local kp = model.keypad
          local qty = ui_logic.clampQty(kp.value, kp.entry.count)
          local got = order.place(ticker, kp.entry.id, qty, model.address)
          model.toast = got > 0
            and ("Ordered " .. got .. "x " .. kp.entry.display .. " -> " .. model.address)
            or "Out of stock"
          model.keypad = nil
        else
          model.keypad.value = ui_logic.stepper(model.keypad.value, b.key, model.keypad.entry.count)
        end
        return
      end
    end
    return
  end

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
  -- скролл-стрелки (на страницу)
  if hit.up and ui_logic.inside(hit.up, x, y) then
    model.scroll = model.scroll - gridPerPage()
    return
  end
  if hit.down and ui_logic.inside(hit.down, x, y) then
    model.scroll = model.scroll + gridPerPage()
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
      model.keypad = { entry = it.entry, value = 0 }
      model.pressed = it.entry.id
      return
    end
  end
end

-- цикл ввода
local function inputLoop()
  while true do
    local ev = { os.pullEvent() }
    local name = ev[1]
    if name == "monitor_touch" then
      handleTouch(ev[3], ev[4])
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

refreshStock()
redraw()
parallel.waitForAll(refreshLoop, inputLoop)
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
  return {
    title  = { x1 = 1,             y1 = 1,     x2 = w, y2 = 1 },
    addr   = { x1 = w - addrW + 1, y1 = 1,     x2 = w, y2 = 1 },
    search = { x1 = 1,             y1 = 2,     x2 = w, y2 = 2 },
    chips  = { x1 = 1,             y1 = 3,     x2 = w, y2 = 3 },
    grid   = { x1 = 1,             y1 = 4,     x2 = w, y2 = h - 2 },
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
function M.chips(groups, x, y, maxW)
  local out = {}
  local cx = x
  for _, g in ipairs(groups) do
    local label = " " .. g .. " "
    local wlab = #label
    if cx - x + wlab > maxW then break end
    out[#out + 1] = { group = g, label = label, rect = { x1 = cx, y1 = y, x2 = cx + wlab - 1, y2 = y } }
    cx = cx + wlab + 1
  end
  return out
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