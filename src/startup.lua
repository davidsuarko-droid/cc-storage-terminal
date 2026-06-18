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
  basket = ui_logic.basketNew(), step = 1,
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
  return ui_logic.gridDims(L.grid, 12, 6, 1).perPage
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
  -- переключатель шага накопления (1 -> 8 -> 64)
  if hit.step and ui_logic.inside(hit.step, x, y) then
    model.step = ui_logic.nextStep(model.step)
    return
  end
  -- очистить корзину
  if hit.clear and ui_logic.inside(hit.clear, x, y) then
    model.basket = ui_logic.basketNew()
    model.toast = "Cart cleared"
    return
  end
  -- подтвердить заказ — послать всю корзину
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
  -- тап плитки = добавить шаг в корзину (накопление)
  for _, it in ipairs(hit.tiles or {}) do
    if ui_logic.inside(it.rect, x, y) then
      ui_logic.basketAdd(model.basket, it.entry, model.step)
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
