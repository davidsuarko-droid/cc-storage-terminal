-- cc-storage-terminal installer. Run: wget run <url>
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

-- высота видимой страницы списка (для скролла на page)
local function gridRows()
  local w, h = monitor.getSize()
  local L = ui_logic.layout(w, h)
  return L.grid.y2 - L.grid.y1 + 1
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
          model.keypad.value = math.min((model.keypad.value * 10) + tonumber(b.key), 9999)
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
  -- скролл-стрелки
  if hit.up and ui_logic.inside(hit.up, x, y) then
    model.scroll = model.scroll - gridRows()
    return
  end
  if hit.down and ui_logic.inside(hit.down, x, y) then
    model.scroll = model.scroll + gridRows()
    return
  end
  for _, c in ipairs(hit.cats or {}) do
    if ui_logic.inside(c.rect, x, y) then
      model.group = c.group
      rebuild()
      return
    end
  end
  for _, it in ipairs(hit.items or {}) do
    if ui_logic.inside(it.rect, x, y) then
      model.keypad = { entry = it.entry, value = 0 }
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
