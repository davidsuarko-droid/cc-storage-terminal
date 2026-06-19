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

local ticker = peripherals.findTicker(config)
-- Бэкенд рендера: есть Tom's GPU → пиксельный render_gpu на его мониторе;
-- нет → символьный render_text на CC-мониторе (старое поведение).
-- Монитор CC требуется ТОЛЬКО для текстового бэкенда: GPU-путь не нуждается в нём.
local backend, surface
local gpu = peripheral.find("tm_gpu")
if gpu then
  backend = require("render_gpu")
  surface = gpu
  local icons = require("icons")
  icons.initRuntime(gpu)
  backend.useIcons(icons)
else
  local monitor = peripherals.findMonitor(config)
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
      model._tap = tostring(ev[2]) .. ":" .. tostring(ev[3]) -- DBG
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
