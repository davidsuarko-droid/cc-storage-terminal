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

-- ===== Рантайм: ленивая загрузка + LRU =====
-- Конфигурируется через DI (тест подменяет fetch/decode/fs).
local cfg = {
  baseUrl = "https://raw.githubusercontent.com/davidsuarko-droid/cc-storage-terminal/main/icons/",
  dir = "/icons",
  limit = 64,
  exists = function(p) return fs and fs.exists(p) end,
  -- читает PNG: сперва с диска, иначе wget по сети, кладёт на диск
  fetch = function(url) return nil end,
  decode = function(bytes) return nil end,
}

-- кэш: map[id]=ref, order = очередь использования (последний — свежий)
local cache = {}
local order = {}

function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  cache = {}; order = {}
end

function M.cacheCount()
  local n = 0
  for _ in pairs(cache) do n = n + 1 end
  return n
end

local function touch(id)
  for i, v in ipairs(order) do
    if v == id then table.remove(order, i); break end
  end
  order[#order + 1] = id
end

local function evictIfNeeded()
  while #order > cfg.limit do
    local victim = table.remove(order, 1)
    local ref = cache[victim]
    cache[victim] = nil
    if ref and ref.free then ref:free() end
  end
end

-- Вернуть image-ref иконки для id или nil (нет файла/сети/декода).
-- Промах кэшируется sentinel-значением false, чтобы повторный вызов
-- не запускал повторный http.get на каждом кадре (блокирующий HTTP-шторм).
function M.get(id)
  local cached = cache[id]
  if cached ~= nil then   -- хит: реальный ref или sentinel false
    touch(id)
    return cached ~= false and cached or nil
  end
  -- кэш холодный — пробуем загрузить
  local bytes = cfg.fetch(cfg.baseUrl .. M.idToFile(id))
  local ref
  if bytes then
    local ok, r = pcall(cfg.decode, bytes)
    if ok and r then ref = r end
  end
  cache[id] = ref or false   -- ref при успехе, false (sentinel) при промахе
  touch(id)
  evictIfNeeded()
  return ref   -- nil при промахе, ref при успехе
end

-- Боевая настройка под CC: чтение с диска или wget, decode через GPU.
function M.initRuntime(gpu)
  M.configure({
    exists = function(p) return fs.exists(p) end,
    fetch = function(url)
      local file = url:match("[^/]+$")
      local path = cfg.dir .. "/" .. file
      if fs.exists(path) then
        local h = fs.open(path, "rb"); local b = h.readAll(); h.close(); return b
      end
      local resp = http and http.get(url, nil, true) -- binary
      if not resp then return nil end
      local b = resp.readAll(); resp.close()
      if b then
        if not fs.exists(cfg.dir) then fs.makeDir(cfg.dir) end
        local h = fs.open(path, "wb"); h.write(b); h.close()
      end
      return b
    end,
    decode = function(bytes) return gpu.decodeImage(bytes) end,
  })
end

return M
