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
