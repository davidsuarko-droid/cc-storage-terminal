# CC:Tweaked Storage Terminal — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Сенсорный терминал-маркетплейс на CC:Tweaked над Create Stock Ticker: смотреть остатки всей базы, искать/листать по категориям, заказывать N штук на выбранный адрес (`Main`/`Core`), авто-обновление ~2с.

**Architecture:** Один Advanced Computer. Чистая логика (нормализация стока, группировка, фильтр поиска, карта имён, адреса, хит-тест, сборка заказа) вынесена в модули без I/O и покрыта юнит-тестами на хост-Lua 5.1. I/O-слой (поиск периферий, рендер монитора, цикл событий) тонкий, smoke-тестируется в CraftOS-PC, финал — in-game. Два параллельных цикла через `parallel.waitForAll`: refresh (таймер) и input (`os.pullEvent`).

**Tech Stack:** Lua 5.1 (семантика ComputerCraft/Cobalt), CC:Tweaked peripheral/term/monitor API, Create 6 `Create_StockTicker` периферия. Тесты: хост-Lua 5.1.5 (локальная сборка) + мок-харнес. Smoke: CraftOS-PC headless.

## Global Constraints

- Lua-диалект — **5.1** (CC использует Cobalt ≈ Lua 5.1). Никакого синтаксиса 5.2+ (`goto`, `\z`, целочисленного деления). Только `string`/`table`/`math` из 5.1.
- Периферии находятся **по типу** (`peripheral.find`), стороны не хардкодятся; конфиг даёт опциональный override через сторону.
- Тип тикера: `Create_StockTicker`. Тип монитора: пробовать `monitor`, затем `monitor_advanced`.
- Адрес доставки по умолчанию — **первый** в `addresses.cfg`. Стартовый список: `Main`, затем `Core`.
- `requestFiltered(address, {name=id, _requestCount=qty})` — порядок аргументов: адрес-строка первым, фильтр-таблица вторым.
- Каждый модуль возвращает таблицу `M` (`return M`); `startup.lua` — единственная точка с `main()`-обвязкой и параллельными циклами.
- Файлы проекта: `scripts/cc-tweaked/storage-terminal/`. Тесты: `scripts/cc-tweaked/storage-terminal/test/`.
- REFRESH = 2 (секунды).

---

## File Structure

Каталог `scripts/cc-tweaked/storage-terminal/`:

| Файл | Ответственность | Тестируется |
|------|-----------------|-------------|
| `config.lua` | Константы: `REFRESH`, опц. `TICKER_SIDE`/`MONITOR_SIDE` | unit (значения) |
| `names.lua` | Карта `id→ярлык`: `parse`, `load`, `label`, `pretty` | unit |
| `addresses.lua` | Список адресов: `parse`, `default` | unit |
| `stock.lua` | Нормализация стока: `group`, `normalize`, `groups` | unit |
| `ui_logic.lua` | Чистая UI-логика: `filter`, `byGroup`, `inside`, `clampQty`, `layout` | unit |
| `peripherals.lua` | Поиск тикера/монитора по типу | smoke |
| `render.lua` | Рендер модели на монитор (использует `ui_logic.layout`) | smoke |
| `order.lua` | `place(ticker,id,qty,address)` → `requestFiltered` | unit |
| `startup.lua` | Загрузка конфигов, два цикла `parallel.waitForAll` | smoke + in-game |
| `names.cfg` | Пример карты имён (редактируется в игре) | — |
| `addresses.cfg` | Список адресов (редактируется в игре) | — |
| `test/mock-cc.lua` | Стабы CC: `colors`, `peripheral`, фейк-тикер, очередь событий | — (харнес) |
| `test/spec.lua` | Юнит-кейсы, запуск `lua5.1 test/spec.lua` | — (раннер) |
| `test/smoke.lua` | CraftOS-PC: грузит модули, без рантайм-ошибок | — |

Разделение `ui_logic.lua` (чистое) vs `render.lua` (I/O) — намеренное: вся хит-тест/раскладка/фильтр-логика юнит-тестируема без монитора, рендер тонкий.

---

### Task 1: Окружение + скаффолд + мок-харнес + config

Поставить хост-Lua 5.1, создать каталог проекта, мок-харнес и первый рабочий модуль (`config.lua`) с проходящим тестом. Деливерабл: `lua5.1 test/spec.lua` зелёный.

**Files:**
- Create: `scripts/cc-tweaked/storage-terminal/config.lua`
- Create: `scripts/cc-tweaked/storage-terminal/test/mock-cc.lua`
- Create: `scripts/cc-tweaked/storage-terminal/test/spec.lua`

**Interfaces:**
- Consumes: ничего.
- Produces:
  - `config` (таблица): `config.REFRESH` (number=2), `config.TICKER_SIDE` (nil|string), `config.MONITOR_SIDE` (nil|string).
  - `mock-cc` (таблица `M`): `M.register(type, obj)`, `M.registerSide(side, obj)`, `M.ticker(stockList)→{stock,requestFiltered,_calls}`, `M.events(list)` (ставит очередь для `os.pullEvent`). Сайд-эффект require: определяет глобалы `colors`, `peripheral`, `os.pullEvent`/`os.startTimer` (переопределение поверх хостового `os`).
  - `spec.lua` хелперы (локальные): `check(name, cond)`, в конце `os.exit(1)` при фейле.

- [ ] **Step 1: Поставить хост-Lua 5.1**

Сначала apt (через `!` в сессии, нужен sudo-пароль пользователя):

```bash
sudo apt-get install -y lua5.1
```

Если sudo недоступен — локальная сборка без root:

```bash
cd /tmp
curl -fsSL https://www.lua.org/ftp/lua-5.1.5.tar.gz -o lua-5.1.5.tar.gz
tar xzf lua-5.1.5.tar.gz
cd lua-5.1.5
# posix-таргет: не требует readline-заголовков
make posix
make local                 # ставит в ./install
mkdir -p ~/.local/bin
cp install/bin/lua ~/.local/bin/lua5.1
```

Проверка: `lua5.1 -v` → `Lua 5.1.5`. Если бинарь в `~/.local/bin`, убедиться что он в `PATH` (`export PATH="$HOME/.local/bin:$PATH"`).

- [ ] **Step 2: Скаффолд каталога**

```bash
mkdir -p /home/davidadmin/claudeproject/scripts/cc-tweaked/storage-terminal/test
```

- [ ] **Step 3: Написать мок-харнес** `test/mock-cc.lua`

```lua
-- Минимальные стабы CC:Tweaked для headless-тестов на хост-Lua 5.1.
local M = {}

-- colors: любой ключ → само имя ключа (рендер не тестируем, важно лишь не падать)
colors = setmetatable({}, { __index = function(_, k) return k end })

-- реестр периферий
local byType, bySide = {}, {}
peripheral = {}
function peripheral.find(t) return byType[t] end
function peripheral.wrap(side) return bySide[side] end
function M.register(t, obj) byType[t] = obj end
function M.registerSide(side, obj) bySide[side] = obj end

-- фейковый Create_StockTicker: stock() отдаёт заданный список,
-- requestFiltered логирует вызовы и возвращает запрошенное количество
function M.ticker(stockList)
  local calls = {}
  return {
    stock = function(_) return stockList end,
    requestFiltered = function(addr, filter)
      calls[#calls + 1] = { addr = addr, filter = filter }
      return filter._requestCount
    end,
    _calls = calls,
  }
end

-- скриптуемая очередь событий для os.pullEvent
local queue = {}
function M.events(list) queue = list end
local realOs = os
os = setmetatable({
  pullEvent = function() return table.remove(queue, 1) end,
  startTimer = function(_) return 1 end,
}, { __index = realOs })

return M
```

- [ ] **Step 4: Написать раннер** `test/spec.lua` (пока только config)

```lua
package.path = "./?.lua;./test/?.lua;" .. package.path
require("mock-cc")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then
    pass = pass + 1
    print("ok   - " .. name)
  else
    fail = fail + 1
    print("FAIL - " .. name)
  end
end

-- config
local config = require("config")
check("REFRESH равен 2", config.REFRESH == 2)
check("TICKER_SIDE по умолчанию nil (авто-детект)", config.TICKER_SIDE == nil)
check("MONITOR_SIDE по умолчанию nil (авто-детект)", config.MONITOR_SIDE == nil)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
```

- [ ] **Step 5: Запустить — убедиться что падает (модуля config нет)**

```bash
cd /home/davidadmin/claudeproject/scripts/cc-tweaked/storage-terminal
lua5.1 test/spec.lua
```

Ожидается: ошибка `module 'config' not found`.

- [ ] **Step 6: Написать** `config.lua`

```lua
-- Конфиг терминала. Стороны nil = авто-детект периферии по типу.
local config = {
  REFRESH      = 2,   -- секунды между обновлениями стока
  TICKER_SIDE  = nil, -- напр. "back" чтобы форсить сторону тикера
  MONITOR_SIDE = nil, -- напр. "left" чтобы форсить сторону монитора
}
return config
```

- [ ] **Step 7: Запустить — зелёный**

```bash
lua5.1 test/spec.lua
```

Ожидается: `3 passed, 0 failed`.

- [ ] **Step 8: Commit**

```bash
git add scripts/cc-tweaked/storage-terminal/config.lua \
        scripts/cc-tweaked/storage-terminal/test/mock-cc.lua \
        scripts/cc-tweaked/storage-terminal/test/spec.lua
git commit -m "feat(storage-terminal): скаффолд, мок-харнес, config"
```

---

### Task 2: names.lua — карта имён + fallback

Кастомные ярлыки `id→имя` из `names.cfg`; fallback на `displayName`, затем красивое имя из id.

**Files:**
- Create: `scripts/cc-tweaked/storage-terminal/names.lua`
- Modify: `scripts/cc-tweaked/storage-terminal/test/spec.lua` (добавить кейсы)

**Interfaces:**
- Consumes: ничего.
- Produces: `names` (таблица `M`):
  - `M.parse(text)` → таблица `{ [id]=label }`. Формат строк `id=label`, `#`-комменты и пустые строки игнор.
  - `M.load(reader)` → заполняет внутреннюю карту; `reader(path)` → string|nil (инъекция для тестов; в игре — чтение файла).
  - `M.label(id, displayName)` → string. Приоритет: карта → `displayName` (если непустой) → `M.pretty(id)`.
  - `M.pretty(id)` → string. `"create:electrum_nugget"` → `"Electrum Nugget"`.
  - `M.reset()` → очистить карту (для изоляции тестов).

- [ ] **Step 1: Добавить падающие тесты в** `test/spec.lua` (перед строкой вывода итога)

```lua
-- names
local names = require("names")
names.reset()
check("pretty: namespace отброшен, слова с заглавной",
  names.pretty("create:electrum_nugget") == "Electrum Nugget")
check("pretty: id без namespace тоже работает",
  names.pretty("apple") == "Apple")
check("parse: id=label, коммент и пустые игнор",
  names.parse("# hdr\nminecraft:apple=Яблоко\n\ncreate:zinc_ingot=Цинк\n")
    ["minecraft:apple"] == "Яблоко")
names.load(function(_) return "minecraft:apple=Яблоко\n" end)
check("label: карта приоритетнее displayName",
  names.label("minecraft:apple", "Apple") == "Яблоко")
check("label: fallback на displayName когда нет в карте",
  names.label("minecraft:gold_nugget", "Gold Nugget") == "Gold Nugget")
check("label: fallback на pretty когда нет ни карты, ни displayName",
  names.label("create:electrum_nugget", nil) == "Electrum Nugget")
```

- [ ] **Step 2: Запустить — падает**

```bash
lua5.1 test/spec.lua
```

Ожидается: ошибка `module 'names' not found`.

- [ ] **Step 3: Написать** `names.lua`

```lua
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
```

- [ ] **Step 4: Запустить — зелёный**

```bash
lua5.1 test/spec.lua
```

Ожидается: `9 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/cc-tweaked/storage-terminal/names.lua \
        scripts/cc-tweaked/storage-terminal/test/spec.lua
git commit -m "feat(storage-terminal): names — карта имён + fallback"
```

---

### Task 3: addresses.lua — список адресов доставки

Парсинг `addresses.cfg`, дефолт-адрес. Пустой/нет файла → `{Main, Core}`.

**Files:**
- Create: `scripts/cc-tweaked/storage-terminal/addresses.lua`
- Create: `scripts/cc-tweaked/storage-terminal/addresses.cfg`
- Modify: `scripts/cc-tweaked/storage-terminal/test/spec.lua`

**Interfaces:**
- Consumes: ничего.
- Produces: `addresses` (таблица `M`):
  - `M.parse(text)` → массив строк-адресов (по строке на адрес, `#`/пустые игнор). Если ничего — `{"Main","Core"}`.
  - `M.default(list)` → `list[1]`.

- [ ] **Step 1: Падающие тесты в** `test/spec.lua`

```lua
-- addresses
local addresses = require("addresses")
local a1 = addresses.parse("Main\nCore\n# коммент\nStorage\n")
check("addresses.parse: 3 адреса", #a1 == 3 and a1[1] == "Main" and a1[3] == "Storage")
local a2 = addresses.parse("# только комменты\n\n")
check("addresses.parse: пусто → дефолт Main,Core", a2[1] == "Main" and a2[2] == "Core")
check("addresses.default: первый в списке", addresses.default(a1) == "Main")
```

- [ ] **Step 2: Запустить — падает** (`module 'addresses' not found`)

```bash
lua5.1 test/spec.lua
```

- [ ] **Step 3: Написать** `addresses.lua`

```lua
-- Список адресов доставки пакетной сети.
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
```

- [ ] **Step 4: Написать** `addresses.cfg`

```
# Адреса доставки пакетной сети Create. По одному на строку.
# Первый = адрес по умолчанию. Редактируется в игре.
Main
Core
```

- [ ] **Step 5: Запустить — зелёный** (`12 passed, 0 failed`)

```bash
lua5.1 test/spec.lua
```

- [ ] **Step 6: Commit**

```bash
git add scripts/cc-tweaked/storage-terminal/addresses.lua \
        scripts/cc-tweaked/storage-terminal/addresses.cfg \
        scripts/cc-tweaked/storage-terminal/test/spec.lua
git commit -m "feat(storage-terminal): addresses — список адресов + дефолт"
```

---

### Task 4: stock.lua — нормализация и группировка стока

`ticker.stock(true)` → отсортированный список `{id,count,display,group}` + список категорий.

**Files:**
- Create: `scripts/cc-tweaked/storage-terminal/stock.lua`
- Modify: `scripts/cc-tweaked/storage-terminal/test/spec.lua`

**Interfaces:**
- Consumes: `names.label(id, displayName)` из Task 2.
- Produces: `stock` (таблица `M`):
  - `M.group(id, itemGroups)` → string. Первый элемент `itemGroups` если есть, иначе namespace из id (до `:`), иначе `"other"`.
  - `M.normalize(raw, names)` → массив `{id, count, display, group}`, сорт по `display` (lower, по возрастанию). `raw` — список вида `{name, count, displayName?, itemGroups?}`.
  - `M.groups(entries)` → массив уникальных групп, отсортированный, с `"All"` первым.

- [ ] **Step 1: Падающие тесты в** `test/spec.lua`

```lua
-- stock
local stock = require("stock")
names.reset()
check("stock.group: первый itemGroup",
  stock.group("create:zinc_ingot", { "Create" }) == "Create")
check("stock.group: fallback на namespace",
  stock.group("minecraft:apple", nil) == "minecraft")
local raw = {
  { name = "minecraft:gold_nugget", count = 5, displayName = "Gold Nugget", itemGroups = { "minecraft" } },
  { name = "create:electrum_nugget", count = 2, itemGroups = { "Create" } },
  { name = "minecraft:apple", count = 9, displayName = "Apple", itemGroups = { "minecraft" } },
}
local norm = stock.normalize(raw, names)
check("stock.normalize: 3 записи", #norm == 3)
check("stock.normalize: сорт по display (Apple первым)", norm[1].display == "Apple")
check("stock.normalize: count проброшен", norm[1].count == 9)
check("stock.normalize: display через names.label (electrum → pretty)",
  (function()
    for _, e in ipairs(norm) do
      if e.id == "create:electrum_nugget" then return e.display == "Electrum Nugget" end
    end
  end)())
local grps = stock.groups(norm)
check("stock.groups: All первым", grps[1] == "All")
check("stock.groups: уникальные Create и minecraft присутствуют",
  (function()
    local has = {}
    for _, g in ipairs(grps) do has[g] = true end
    return has["Create"] and has["minecraft"]
  end)())
```

- [ ] **Step 2: Запустить — падает** (`module 'stock' not found`)

```bash
lua5.1 test/spec.lua
```

- [ ] **Step 3: Написать** `stock.lua`

```lua
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
```

- [ ] **Step 4: Запустить — зелёный** (`20 passed, 0 failed`)

```bash
lua5.1 test/spec.lua
```

- [ ] **Step 5: Commit**

```bash
git add scripts/cc-tweaked/storage-terminal/stock.lua \
        scripts/cc-tweaked/storage-terminal/test/spec.lua
git commit -m "feat(storage-terminal): stock — нормализация + группировка"
```

---

### Task 5: ui_logic.lua — чистая UI-логика

Фильтр поиска, фильтр по группе, хит-тест прямоугольника, зажатие количества, раскладка сетки/категорий.

**Files:**
- Create: `scripts/cc-tweaked/storage-terminal/ui_logic.lua`
- Modify: `scripts/cc-tweaked/storage-terminal/test/spec.lua`

**Interfaces:**
- Consumes: ничего.
- Produces: `ui_logic` (таблица `M`):
  - `M.filter(entries, query)` → подмассив, где `query` (lower, подстрока) встречается в `display` или `id`. Пустой query → исходный массив.
  - `M.byGroup(entries, group)` → подмассив с `entry.group == group`. `group=="All"`/nil → исходный.
  - `M.inside(rect, x, y)` → bool. `rect = {x1,y1,x2,y2}`, границы включительно.
  - `M.clampQty(n, max)` → number в `[1, max]` (если `max<1`, вернуть 0).
  - `M.layout(w, h)` → таблица зон: `{ search={x1,y1,x2,y2}, cats={x1,y1,x2,y2}, grid={x1,y1,x2,y2}, addr={x1,y1,x2,y2} }`. Раскладка: строка поиска сверху (y=1), полоса адреса снизу (y=h), левая колонка категорий (ширина 12), сетка справа между ними.

- [ ] **Step 1: Падающие тесты в** `test/spec.lua`

```lua
-- ui_logic
local ui = require("ui_logic")
local items = {
  { id = "minecraft:apple",        display = "Apple",          group = "minecraft" },
  { id = "create:electrum_nugget", display = "Electrum Nugget", group = "Create" },
  { id = "create:zinc_ingot",      display = "Цинк",            group = "Create" },
}
check("filter: по display (без регистра)", #ui.filter(items, "apple") == 1)
check("filter: по id-подстроке", #ui.filter(items, "electrum") == 1)
check("filter: пустой query → всё", #ui.filter(items, "") == 3)
check("filter: нет совпадений → пусто", #ui.filter(items, "zzz") == 0)
check("byGroup: Create → 2", #ui.byGroup(items, "Create") == 2)
check("byGroup: All → всё", #ui.byGroup(items, "All") == 3)
local r = { x1 = 2, y1 = 2, x2 = 5, y2 = 5 }
check("inside: внутри", ui.inside(r, 3, 4) == true)
check("inside: на границе включительно", ui.inside(r, 5, 5) == true)
check("inside: снаружи", ui.inside(r, 6, 4) == false)
check("clampQty: ниже 1 → 1", ui.clampQty(0, 64) == 1)
check("clampQty: выше max → max", ui.clampQty(99, 64) == 64)
check("clampQty: в диапазоне без изменений", ui.clampQty(10, 64) == 10)
check("clampQty: max<1 → 0", ui.clampQty(5, 0) == 0)
local L = ui.layout(50, 19)
check("layout: search сверху (y1=1)", L.search.y1 == 1)
check("layout: addr снизу (y2=19)", L.addr.y2 == 19)
check("layout: cats слева ширина 12", L.cats.x2 == 12)
check("layout: grid правее cats", L.grid.x1 == 13)
```

- [ ] **Step 2: Запустить — падает** (`module 'ui_logic' not found`)

```bash
lua5.1 test/spec.lua
```

- [ ] **Step 3: Написать** `ui_logic.lua`

```lua
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
```

- [ ] **Step 4: Запустить — зелёный** (`38 passed, 0 failed`)

```bash
lua5.1 test/spec.lua
```

- [ ] **Step 5: Commit**

```bash
git add scripts/cc-tweaked/storage-terminal/ui_logic.lua \
        scripts/cc-tweaked/storage-terminal/test/spec.lua
git commit -m "feat(storage-terminal): ui_logic — фильтры, хит-тест, раскладка"
```

---

### Task 6: order.lua — размещение заказа

Тонкая обёртка `requestFiltered`. Тестируется через фейк-тикер из мок-харнеса.

**Files:**
- Create: `scripts/cc-tweaked/storage-terminal/order.lua`
- Modify: `scripts/cc-tweaked/storage-terminal/test/spec.lua`

**Interfaces:**
- Consumes: фейк-тикер `mock.ticker(...)` (метод `requestFiltered(addr, filter)`).
- Produces: `order` (таблица `M`):
  - `M.place(ticker, id, qty, address)` → number (сколько реально заказано). Зовёт `ticker.requestFiltered(address, {name=id, _requestCount=qty})`.

- [ ] **Step 1: Падающие тесты в** `test/spec.lua`

```lua
-- order
local mock = require("mock-cc")
local order = require("order")
local tk = mock.ticker({})
local got = order.place(tk, "minecraft:apple", 10, "Core")
check("order.place: возвращает кол-во из requestFiltered", got == 10)
check("order.place: адрес передан первым аргументом", tk._calls[1].addr == "Core")
check("order.place: filter.name = id", tk._calls[1].filter.name == "minecraft:apple")
check("order.place: filter._requestCount = qty", tk._calls[1].filter._requestCount == 10)
```

- [ ] **Step 2: Запустить — падает** (`module 'order' not found`)

```bash
lua5.1 test/spec.lua
```

- [ ] **Step 3: Написать** `order.lua`

```lua
-- Размещение заказа на адрес пакетной сети.
local M = {}

function M.place(ticker, id, qty, address)
  return ticker.requestFiltered(address, { name = id, _requestCount = qty })
end

return M
```

- [ ] **Step 4: Запустить — зелёный** (`42 passed, 0 failed`)

```bash
lua5.1 test/spec.lua
```

- [ ] **Step 5: Commit**

```bash
git add scripts/cc-tweaked/storage-terminal/order.lua \
        scripts/cc-tweaked/storage-terminal/test/spec.lua
git commit -m "feat(storage-terminal): order — requestFiltered обёртка"
```

---

### Task 7: peripherals.lua + render.lua — I/O-слой

Поиск периферий по типу и рендер модели на монитор. Юнит-тестов нет (I/O); корректность ловится Task 8 smoke + in-game. Код полный.

**Files:**
- Create: `scripts/cc-tweaked/storage-terminal/peripherals.lua`
- Create: `scripts/cc-tweaked/storage-terminal/render.lua`

**Interfaces:**
- Consumes: `config` (Task 1), `ui_logic.layout` (Task 5).
- Produces:
  - `peripherals` (таблица `M`): `M.find(config)` → `ticker, monitor`. Бросает `error(msg)` с понятным текстом если что-то не найдено.
  - `render` (таблица `M`): `M.draw(monitor, model)`. `model` = `{ items, groups, group, query, searchFocus, address, addresses, toast, keypad }` (см. Task 8 для полей). Рисует поиск/категории/сетку/адрес/тост/кейпад. Возвращает `hit` — таблицу зон для хит-теста: `{ search, cats={{rect,group}...}, items={{rect,entry}...}, addr, keypad={{rect,key}...} }`.

- [ ] **Step 1: Написать** `peripherals.lua`

```lua
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
```

- [ ] **Step 2: Написать** `render.lua`

```lua
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
    " Поиск: " .. (model.query ~= "" and model.query or "...") , sfg, sbg)
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
    local keys = { "1","2","3","4","5","6","7","8","9","0","OK","X" }
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
```

- [ ] **Step 3: Sanity-load обоих модулей под мок-харнесом**

Добавить временную проверку, что модули грузятся (рендер требует методы монитора — фейк-монитор в мок):

```bash
cd /home/davidadmin/claudeproject/scripts/cc-tweaked/storage-terminal
lua5.1 -e 'package.path="./?.lua;./test/?.lua;"..package.path; require("mock-cc"); require("peripherals"); require("render"); print("modules load OK")'
```

Ожидается: `modules load OK` (синтаксис валиден). Рендер-вывод проверяется в Task 8.

- [ ] **Step 4: Commit**

```bash
git add scripts/cc-tweaked/storage-terminal/peripherals.lua \
        scripts/cc-tweaked/storage-terminal/render.lua
git commit -m "feat(storage-terminal): peripherals + render (I/O-слой)"
```

---

### Task 8: startup.lua — обвязка, циклы, smoke + in-game

Связать всё: загрузка конфигов, поиск периферий, модель состояния, два параллельных цикла. Smoke в CraftOS-PC, финальная проверка in-game.

**Files:**
- Create: `scripts/cc-tweaked/storage-terminal/startup.lua`
- Create: `scripts/cc-tweaked/storage-terminal/names.cfg`
- Create: `scripts/cc-tweaked/storage-terminal/test/smoke.lua`

**Interfaces:**
- Consumes: все модули Task 1–7. Модель `model` с полями: `items, groups, group, query, searchFocus, address, addresses, addrIdx, toast, keypad`. `keypad = { entry, value }` или nil.
- Produces: исполняемая программа (запускается как `startup` на компьютере).

- [ ] **Step 1: Написать** `names.cfg` (пример, редактируется в игре)

```
# Кастомные имена: id=ярлык. Редактируется в игре (edit names.cfg).
# Пример:
# minecraft:gold_nugget=Золотой самородок
# create:electrum_nugget=Электрум
```

- [ ] **Step 2: Написать** `startup.lua`

```lua
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
```

- [ ] **Step 3: Установить CraftOS-PC (headless smoke)**

По порядку, первый рабочий вариант:

```bash
# 1) snap (если доступен store + sudo)
sudo snap install craftos-pc
# 2) иначе AppImage с GitHub releases (MCJack123/craftos2):
cd /tmp
curl -fsSL -o craftos.AppImage \
  "$(curl -fsSL https://api.github.com/repos/MCJack123/craftos2/releases/latest \
    | grep browser_download_url | grep AppImage | head -1 | cut -d'"' -f4)"
chmod +x craftos.AppImage
./craftos.AppImage --appimage-extract     # если FUSE недоступен
# бинарь: /tmp/squashfs-root/usr/bin/craftos
```

Проверка: `craftos --version` (или `./squashfs-root/usr/bin/craftos --version`).

- [ ] **Step 4: Написать** `test/smoke.lua` (грузит startup без периферий → ожидаем понятную ошибку, не синтаксис-краш)

```lua
-- Smoke: проверяем, что startup парсится и падает ИМЕННО на отсутствии тикера
-- (а не на синтаксической/рантайм-ошибке в модулях).
package.path = "./?.lua;./test/?.lua;" .. package.path
require("mock-cc")
-- fs/keys/parallel-стабы, которых нет в хост-Lua
fs = { exists = function() return false end }
keys = { backspace = 259, enter = 257 }
parallel = { waitForAll = function() end }
local ok, err = pcall(function() dofile("startup.lua") end)
assert(not ok, "ожидалась ошибка (нет тикера), но startup не упал")
assert(tostring(err):find("Create_StockTicker"),
  "ожидалась ошибка про Create_StockTicker, получили: " .. tostring(err))
print("smoke OK — startup грузится, периферия валидируется")
```

- [ ] **Step 5: Запустить smoke на хост-Lua**

```bash
cd /home/davidadmin/claudeproject/scripts/cc-tweaked/storage-terminal
lua5.1 test/smoke.lua
```

Ожидается: `smoke OK — startup грузится, периферия валидируется`.

- [ ] **Step 6: Полный прогон юнит-тестов (регрессия)**

```bash
lua5.1 test/spec.lua
```

Ожидается: `42 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add scripts/cc-tweaked/storage-terminal/startup.lua \
        scripts/cc-tweaked/storage-terminal/names.cfg \
        scripts/cc-tweaked/storage-terminal/test/smoke.lua
git commit -m "feat(storage-terminal): startup + smoke — циклы refresh/input"
```

- [ ] **Step 8: In-game проверка (пользователь)**

Расстановка: справа компьютера — Stock Ticker, сзади — склад, слева — Advanced Monitor.
Деплой: скопировать содержимое `storage-terminal/` на компьютер (`pastebin`/`wget` по файлам, либо копия в `world/computercraft/computer/<id>/`), `startup.lua` как автозапуск, ребут.

Чек-лист:
1. Грузится без ошибок, монитор показывает поиск + категории + сетку + полосу адреса.
2. Остатки обновляются ~каждые 2с.
3. Тап по категории фильтрует список.
4. Тап по полю поиска → фокус (жёлтый); печать на клаве компа фильтрует живьём; backspace стирает.
5. Тап по полосе адреса переключает `Main`↔`Core`.
6. Тап по предмету → кейпад; набрать `1`, `OK` → тост «Заказано 1x… -> <адрес>», посылка приходит в выбранный адрес.

---

## Self-Review

**1. Spec coverage:**
- Остатки всей базы через `stock(true)` → Task 4 `normalize` + Task 8 `refreshStock`. ✓
- Категории + поиск → Task 5 `byGroup`/`filter`, Task 7 render, Task 8 input. ✓
- Поиск с физической клавы при фокусе → Task 8 `char`/`key` + `searchFocus`. ✓
- Заказ N штук → Task 6 `order.place` + Task 8 кейпад. ✓
- Мультиадрес `Main`/`Core` из `addresses.cfg`, выбор в UI → Task 3 + Task 8 полоса адреса. ✓
- Кастомные имена из `names.cfg` + fallback → Task 2. ✓
- Авто-детект периферий по типу, override стороной → Task 7 `peripherals.find` + config. ✓
- Авто-обновление 2с → Task 8 `refreshLoop` + `REFRESH`. ✓
- Обработка ошибок (нет периферии / сеть упала / clamp кол-ва) → Task 7 `error`, Task 8 `pcall`+toast, Task 5 `clampQty`. ✓
- Тестирование: lua5.1 mock + CraftOS smoke + in-game → Task 1–8. ✓
- Отложено SP2 (DPS) / SP3 (крафт) — в плане не реализуется, корректно. ✓

**2. Placeholder scan:** код в каждом шаге полный, плейсхолдеров нет. ✓

**3. Type consistency:**
- `names.label(id, displayName)` — определён Task 2, вызван так же в Task 4 `normalize`. ✓
- `stock.normalize(raw, names)` поля `{id,count,display,group}` — те же в Task 5/7/8. ✓
- `ui_logic.inside(rect,x,y)`, `rect={x1,y1,x2,y2}` — единый формат в render/startup. ✓
- `order.place(ticker,id,qty,address)` — Task 6 = вызов в Task 8. ✓
- `peripherals.find(config)→ticker,monitor` — Task 7 = Task 8. ✓
- `render.draw(monitor,model)→hit` поля `{search,cats,items,addr,keypad}` — Task 7 = хит-тест Task 8. ✓
- `addresses.parse`/`default` — Task 3 = Task 8. ✓

Расхождений нет.
