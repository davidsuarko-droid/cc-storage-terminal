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
