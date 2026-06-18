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
