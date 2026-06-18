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
-- Рендер модели на монитор. Возвращает зоны для хит-теста.
local ui_logic = require("ui_logic")
local M = {}

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

function M.draw(monitor, model)
  monitor.setTextScale(0.5)
  local w, h = monitor.getSize()
  local L = ui_logic.layout(w, h)
  monitor.setBackgroundColor(colors.black)
  monitor.clear()
  local hit = { cats = {}, items = {}, keypad = {} }

  -- строка поиска
  local sfg = model.searchFocus and colors.black or colors.white
  local sbg = model.searchFocus and colors.yellow or colors.gray
  fill(monitor, L.search, sbg)
  text(monitor, L.search.x1, L.search.y1,
    " Поиск: " .. (model.query ~= "" and model.query or "..."), sfg, sbg)
  hit.search = L.search

  -- категории (левая колонка)
  fill(monitor, L.cats, colors.gray)
  local cy = L.cats.y1
  for _, g in ipairs(model.groups) do
    if cy > L.cats.y2 then break end
    local active = (g == model.group)
    local bg = active and colors.cyan or colors.gray
    local rect = { x1 = L.cats.x1, y1 = cy, x2 = L.cats.x2, y2 = cy }
    fill(monitor, rect, bg)
    text(monitor, L.cats.x1, cy, g:sub(1, L.cats.x2 - L.cats.x1 + 1), colors.white, bg)
    hit.cats[#hit.cats + 1] = { rect = rect, group = g }
    cy = cy + 1
  end

  -- сетка предметов
  fill(monitor, L.grid, colors.black)
  local gy = L.grid.y1
  for _, e in ipairs(model.items) do
    if gy > L.grid.y2 then break end
    local rect = { x1 = L.grid.x1, y1 = gy, x2 = L.grid.x2, y2 = gy }
    local line = string.format("%-24s x%d", e.display:sub(1, 24), e.count)
    text(monitor, L.grid.x1, gy, line, colors.white, colors.black)
    hit.items[#hit.items + 1] = { rect = rect, entry = e }
    gy = gy + 1
  end

  -- полоса адреса
  fill(monitor, L.addr, colors.green)
  text(monitor, L.addr.x1, L.addr.y1,
    " Доставка: " .. model.address .. "  (тап — сменить)", colors.white, colors.green)
  hit.addr = L.addr

  -- тост
  if model.toast then
    local ty = h - 2
    text(monitor, L.grid.x1, ty, model.toast, colors.black, colors.yellow)
  end

  -- кейпад количества (оверлей по центру)
  if model.keypad then
    local kx, ky = math.floor(w / 2) - 8, math.floor(h / 2) - 4
    local panel = { x1 = kx, y1 = ky, x2 = kx + 16, y2 = ky + 8 }
    fill(monitor, panel, colors.gray)
    text(monitor, kx + 1, ky, ("%s: %d"):format(model.keypad.entry.display:sub(1, 12),
      model.keypad.value), colors.white, colors.gray)
    local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "OK", "X" }
    local i = 0
    for _, k in ipairs(keys) do
      local col = i % 3
      local row = math.floor(i / 3)
      local rect = { x1 = kx + 1 + col * 5, y1 = ky + 2 + row, x2 = kx + 4 + col * 5, y2 = ky + 2 + row }
      fill(monitor, rect, colors.lightGray)
      text(monitor, rect.x1, rect.y1, (" " .. k):sub(1, 4), colors.black, colors.lightGray)
      hit.keypad[#hit.keypad + 1] = { rect = rect, key = k }
      i = i + 1
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
  query = "", searchFocus = false,
  addresses = addrList, addrIdx = 1, address = addresses.default(addrList),
  toast = nil, keypad = nil,
}
local allItems = {}
local hit = {}

local function rebuild()
  local list = ui_logic.byGroup(allItems, model.group)
  model.items = ui_logic.filter(list, model.query)
end

local function refreshStock()
  local ok, raw = pcall(function() return ticker.stock(true) end)
  if ok and raw then
    allItems = stock.normalize(raw, names)
    model.groups = stock.groups(allItems)
    rebuild()
  else
    model.toast = "Сеть недоступна"
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
            and ("Заказано " .. got .. "x" .. kp.entry.display .. " -> " .. model.address)
            or "Нет в наличии"
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
]=]
F["ui_logic.lua"] = [=[
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
]=]
F["names.cfg"] = [=[
# Кастомные имена: id=ярлык. Редактируется в игре (edit names.cfg).
# Пример:
# minecraft:gold_nugget=Золотой самородок
# create:electrum_nugget=Электрум
]=]
F["addresses.cfg"] = [=[
# Адреса доставки пакетной сети Create. По одному на строку.
# Первый = адрес по умолчанию. Редактируется в игре.
Main
Core
]=]
for name, body in pairs(F) do
  -- не перезатирать пользовательские .cfg, если уже есть
  if name:match("%.cfg$") and fs.exists(name) then
    print("skip "..name.." (есть)")
  else
    local h = fs.open(name, "w"); h.write(body); h.close()
    print("write "..name)
  end
end
print("Готово. Ребут или: startup")
