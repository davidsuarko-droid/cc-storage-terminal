-- Иконки предметов для GPU-бэкенда. Чистые помощники (маппинг id→файл,
-- разбор item-модели) + рантайм-загрузка (ленивый wget + decodeImage + LRU).
-- Рантайм-часть использует CC API (fs/http), под тестом не вызывается.
local M = {}

-- id предмета → имя файла иконки. namespace:name → ns__name.png.
-- Без namespace считаем minecraft.
function M.idToFile(id)
  local ns, name = id:match("^(.-):(.+)$")
  if not ns then ns, name = "minecraft", id end
  return ns .. "__" .. name .. ".png"
end

-- Из таблицы item-модели достать layer0 (плоская item-текстура).
-- Возвращает строку-путь текстуры или nil (3D/блок-модель — пропускаем).
function M.parseLayer0(model)
  if not model or type(model) ~= "table" then return nil end
  local parent = model.parent or ""
  -- item/generated и item/handheld — плоские item-модели со слоями
  local isItem = parent:find("item/generated", 1, true) or parent:find("item/handheld", 1, true)
  if not isItem then return nil end
  if model.textures and model.textures.layer0 then return model.textures.layer0 end
  return nil
end

return M
