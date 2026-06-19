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

-- M.draw реализуется в Task 2.4.
function M.draw(surface, model)
  return { tiles = {}, chips = {} }
end

return M
