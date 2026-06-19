package.path = "./src/?.lua;./test/?.lua;" .. package.path
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

-- addresses
local addresses = require("addresses")
local a1 = addresses.parse("Main\nCore\n# коммент\nStorage\n")
check("addresses.parse: 3 адреса", #a1 == 3 and a1[1] == "Main" and a1[3] == "Storage")
local a2 = addresses.parse("# только комменты\n\n")
check("addresses.parse: пусто → дефолт Main,Core", a2[1] == "Main" and a2[2] == "Core")
check("addresses.default: первый в списке", addresses.default(a1) == "Main")

-- classify (таксономия)
local classify = require("classify")
check("classify: create:* → Create", classify.of("create:cogwheel", nil) == "Create")
check("classify: createaddition:* → Create", classify.of("createaddition:copper_wire", nil) == "Create")
check("classify: piston → Redstone", classify.of("minecraft:piston", nil) == "Redstone")
check("classify: redstone_torch → Redstone", classify.of("minecraft:redstone_torch", nil) == "Redstone")
check("classify: lever → Redstone", classify.of("minecraft:lever", nil) == "Redstone")
check("classify: redstone_block → Redstone (раньше Building)",
  classify.of("minecraft:redstone_block", nil) == "Redstone")
check("classify: redstone_ore → Resources (не Redstone)",
  classify.of("minecraft:redstone_ore", nil) == "Resources")
check("classify: iron_ingot → Resources", classify.of("minecraft:iron_ingot", nil) == "Resources")
check("classify: по тегу c:nuggets → Resources",
  classify.of("minecraft:gold_nugget", { "c:nuggets" }) == "Resources")
check("classify: oak_planks → Wood (раньше Building)", classify.of("minecraft:oak_planks", nil) == "Wood")
check("classify: oak_log → Wood", classify.of("minecraft:oak_log", nil) == "Wood")
check("classify: по тегу minecraft:logs → Wood",
  classify.of("minecraft:weird", { "minecraft:logs" }) == "Wood")
check("classify: cobblestone → Stone", classify.of("minecraft:cobblestone", nil) == "Stone")
check("classify: white_wool → Building", classify.of("minecraft:white_wool", nil) == "Building")
check("classify: apple → Other", classify.of("minecraft:apple", nil) == "Other")
check("classify.order: Create<Resources<Building",
  classify.order("Create") < classify.order("Resources")
    and classify.order("Resources") < classify.order("Building"))
check("classify.order: Other последний", classify.order("Other") == 7)

-- stock
local stock = require("stock")
names.reset()
local raw = {
  { name = "minecraft:gold_nugget", count = 5, displayName = "Gold Nugget", tags = { "c:nuggets" } },
  { name = "create:electrum_nugget", count = 2 },
  { name = "minecraft:apple", count = 9, displayName = "Apple" },
}
local norm = stock.normalize(raw, names)
check("stock.normalize: 3 записи", #norm == 3)
check("stock.normalize: сорт по display (Apple первым)", norm[1].display == "Apple")
check("stock.normalize: count проброшен", norm[1].count == 9)
check("stock.normalize: группа через classify (gold_nugget по тегу → Resources)",
  (function()
    for _, e in ipairs(norm) do
      if e.id == "minecraft:gold_nugget" then return e.group == "Resources" end
    end
  end)())
check("stock.normalize: create:electrum_nugget → Create",
  (function()
    for _, e in ipairs(norm) do
      if e.id == "create:electrum_nugget" then return e.group == "Create" end
    end
  end)())
local grps = stock.groups(norm)
check("stock.groups: All первым", grps[1] == "All")
check("stock.groups: Create раньше Resources раньше Other (по рангу)",
  (function()
    local pos = {}
    for i, g in ipairs(grps) do pos[g] = i end
    return pos["Create"] < pos["Resources"] and pos["Resources"] < pos["Other"]
  end)())

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
local Lay = ui.layout(50, 19)
check("layout: title сверху (y1=1)", Lay.title.y1 == 1)
check("layout: addr-кнопка в title справа (x2=w)", Lay.addr.x2 == 50 and Lay.addr.y1 == 1)
check("layout: search вторая строка (y1=2)", Lay.search.y1 == 2)
check("layout: chips две строки (y1=3, y2=4)", Lay.chips.y1 == 3 and Lay.chips.y2 == 4 and Lay.chips.x1 == 1)
check("layout: grid на всю ширину под чипами (x1=1, y1=5)", Lay.grid.x1 == 1 and Lay.grid.y1 == 5)
check("layout: grid не залезает на нижний блок (y2=h-cartH=15)", Lay.grid.y2 == 15)
check("layout: cart-панель снизу-слева (3 ряда, y2=h-1, x1=1)", Lay.cart.y2 == 18 and Lay.cart.x1 == 1)
check("layout: cart уже половины ширины", Lay.cart.x2 == 21)
check("layout: правая колонка после корзины (scroll/status)", Lay.scroll.x1 == 23 and Lay.status.x1 == 23)
check("layout: status в правой колонке (y1=by+1=17)", Lay.status.y1 == 17)
check("layout: btns во всю ширину снизу (x1=1, y1=h)", Lay.btns.x1 == 1 and Lay.btns.y1 == 19)

-- gridDims (раскладка плиток)
local dims = ui.gridDims({ x1 = 1, y1 = 4, x2 = 50, y2 = 17 }, 9, 5, 1)
check("gridDims: cols по ширине ((50+1)/(9+1)=5)", dims.cols == 5)
check("gridDims: rows по высоте ((14+1)/(5+1)=2)", dims.rows == 2)
check("gridDims: perPage = cols*rows", dims.perPage == 10)

-- tiles (позиции плиток страницы)
local gi = {}
for i = 1, 25 do gi[i] = { id = "g" .. i, display = "G" .. i } end
local tl, tpg = ui.tiles(gi, 0, dims, { x = 1, y = 4 })
check("tiles: 10 плиток на странице", #tl == 10)
check("tiles: первая в origin", tl[1].rect.x1 == 1 and tl[1].rect.y1 == 4)
check("tiles: вторая со сдвигом на tileW+gap", tl[2].rect.x1 == 11 and tl[2].rect.y1 == 4)
check("tiles: шестая на втором ряду", tl[6].rect.x1 == 1 and tl[6].rect.y1 == 10)
check("tiles: page прокидывает hasDown", tpg.hasDown == true)
local tl2 = ui.tiles(gi, 10, dims, { x = 1, y = 4 })
check("tiles: вторая страница начинается с g11", tl2[1].entry.id == "g11")

-- chips (горизонтальные категории)
local ch = ui.chips({ "All", "Create", "Redstone" }, 1, 3, 50)
check("chips: 3 чипа", #ch == 3)
check("chips: первый с группой All в y=3", ch[1].group == "All" and ch[1].rect.y1 == 3)
check("chips: второй правее первого", ch[2].rect.x1 > ch[1].rect.x2)
local chN = ui.chips({ "All", "Create", "Redstone" }, 1, 3, 8)
check("chips: узкая ширина обрезает список", #chN < 3)
local ch2 = ui.chips({ "All" }, 1, 3, 50, 2)
check("chips: height=2 даёт двустрочную тап-зону", ch2[1].rect.y1 == 3 and ch2[1].rect.y2 == 4)

-- wrap2 (перенос имени на 2 строки)
local wA = ui.wrap2("Iron", 10)
check("wrap2: короткое влезает в одну строку", wA[1] == "Iron" and wA[2] == "")
local wB = ui.wrap2("Iron Ingot", 6)
check("wrap2: рвёт по пробелу", wB[1] == "Iron" and wB[2] == "Ingot")
local wC = ui.wrap2("Andesite Alloy Block", 6)
check("wrap2: вторая строка обрезается с ..", wC[1] == "Andesi" and wC[2]:sub(-2) == "..")
local wD = ui.wrap2("Supercalifragilistic", 6)
check("wrap2: длинное слово режется без пробела", wD[1] == "Superc")

-- stepper (математика выбора количества)
check("stepper: + прибавляет 1", ui.stepper(5, "+", 64) == 6)
check("stepper: - убавляет 1", ui.stepper(5, "-", 64) == 4)
check("stepper: +8", ui.stepper(0, "+8", 64) == 8)
check("stepper: +64 клампится к max", ui.stepper(10, "+64", 64) == 64)
check("stepper: Max = весь сток", ui.stepper(0, "Max", 42) == 42)
check("stepper: Clear = 0", ui.stepper(30, "Clear", 64) == 0)
check("stepper: не уходит ниже 0", ui.stepper(0, "-", 64) == 0)

-- basket (корзина-накопление)
local bIron = { id = "iron", display = "Iron", count = 100 }
local bGold = { id = "gold", display = "Gold", count = 50 }
local bk = ui.basketNew()
check("basket: новая пустая", ui.basketTotals(bk).lines == 0)
ui.basketAdd(bk, bIron, 8)
check("basket: add 8 → qty 8", ui.basketQty(bk, "iron") == 8)
ui.basketAdd(bk, bIron, 64)
check("basket: накапливает (8+64=72)", ui.basketQty(bk, "iron") == 72)
ui.basketAdd(bk, bGold, 1)
check("basket: вторая позиция", ui.basketTotals(bk).lines == 2)
check("basket: units = сумма (72+1)", ui.basketTotals(bk).units == 73)
ui.basketAdd(bk, bIron, 999)
check("basket: кламп к stock (count=100)", ui.basketQty(bk, "iron") == 100)
check("basket: порядок добавления сохранён", ui.basketList(bk)[1].entry.id == "iron")
ui.basketAdd(bk, bGold, -5)
check("basket: уход в 0/ниже → убрать позицию", ui.basketQty(bk, "gold") == 0 and ui.basketTotals(bk).lines == 1)
check("basket: nextStep 1→8→64→1",
  ui.nextStep(1) == 8 and ui.nextStep(8) == 64 and ui.nextStep(64) == 1)

-- sprites (сикстант-энкодер)
local sprites = require("sprites")
local function bit(n, i) return math.floor(n / 2 ^ (i - 1)) % 2 == 1 end
check("sprites.cell: пусто → 128, без инверсии",
  (function() local c, inv = sprites.cell(false, false, false, false, false, false)
    return c == 128 and inv == false end)())
check("sprites.cell: всё вкл → 128 + инверсия",
  (function() local c, inv = sprites.cell(true, true, true, true, true, true)
    return c == 128 and inv == true end)())
check("sprites.cell: только TL → 129", (sprites.cell(true, false, false, false, false, false)) == 129)
check("sprites.cell: TL+TR → 131", (sprites.cell(true, true, false, false, false, false)) == 131)
check("sprites.cell: роундтрип произвольного паттерна",
  (function()
    local p = { true, false, true, true, false, false } -- TL,TR,ML,MR,BL,BR
    local c, inv = sprites.cell(p[1], p[2], p[3], p[4], p[5], p[6])
    local n = c - 128
    for i = 1, 5 do
      local got = (bit(n, i) ~= inv) -- p_i = stored XOR invert
      if got ~= p[i] then return false end
    end
    return (p[6] and true or false) == inv
  end)())
check("sprites: спрайт на каждую категорию существует",
  (function()
    for _, name in ipairs({ "Create", "Redstone", "Resources", "Wood", "Stone", "Building", "Other" }) do
      local s = sprites.SPRITES[name]
      if not s or #s ~= 6 or #s[1] ~= 4 then return false end
    end
    return true
  end)())

-- page (пагинация/скролл)
local many = {}
for i = 1, 10 do many[i] = { id = "i" .. i, display = "I" .. i } end
local p0 = ui.page(many, 0, 4)
check("page: первая страница 4 строки", #p0.slice == 4 and p0.slice[1].id == "i1")
check("page: hasUp=false на верху", p0.hasUp == false)
check("page: hasDown=true есть ещё", p0.hasDown == true)
local p1 = ui.page(many, 99, 4)
check("page: scroll клампится к max (6)", p1.scroll == 6)
check("page: последняя страница i7..i10", p1.slice[1].id == "i7" and #p1.slice == 4)
check("page: hasDown=false внизу", p1.hasDown == false)
check("page: hasUp=true внизу", p1.hasUp == true)
check("page: rows>=n → одна страница, без скролла",
  (function() local p = ui.page(many, 0, 20); return #p.slice == 10 and p.hasDown == false end)())

-- order
local mock = require("mock-cc")
local order = require("order")
local tk = mock.ticker({})
local got = order.place(tk, "minecraft:apple", 10, "Core")
check("order.place: возвращает кол-во из requestFiltered", got == 10)
check("order.place: адрес передан первым аргументом", tk._calls[1].addr == "Core")
check("order.place: filter.name = id", tk._calls[1].filter.name == "minecraft:apple")
check("order.place: filter._requestCount = qty", tk._calls[1].filter._requestCount == 10)

-- net (протокол)
local net = require("net")
check("net.PROTO задан", net.PROTO == "ccstore")
check("net.reqStock тип stock", net.reqStock().t == "stock")
local rs = net.respStock({ { id = "a" } }, { "Main" })
check("net.respStock несёт items", rs.items[1].id == "a")
check("net.respStock несёт addresses", rs.addresses[1] == "Main")
local ro = net.reqOrder("minecraft:apple", 5, "Core")
check("net.reqOrder поля", ro.t == "order" and ro.id == "minecraft:apple" and ro.qty == 5 and ro.address == "Core")
check("net.respOrder.got", net.respOrder(7).got == 7)
check("net.kind читает t", net.kind({ t = "stock" }) == "stock")
check("net.kind на не-таблице nil", net.kind("nope") == nil)
check("net.kind на nil nil", net.kind(nil) == nil)

-- icons: чистые помощники маппинга
local icons = require("icons")
check("idToFile: namespace:name -> ns__name.png",
  icons.idToFile("create:cogwheel") == "create__cogwheel.png")
check("idToFile: без namespace -> minecraft__name.png",
  icons.idToFile("apple") == "minecraft__apple.png")
check("parseLayer0: item/generated отдаёт layer0",
  icons.parseLayer0({ parent = "minecraft:item/generated",
    textures = { layer0 = "create:item/cogwheel" } }) == "create:item/cogwheel")
check("parseLayer0: 3D/блок-модель без layer0 -> nil",
  icons.parseLayer0({ parent = "create:block/cogwheel" }) == nil)
check("parseLayer0: handheld тоже item-модель -> layer0",
  icons.parseLayer0({ parent = "minecraft:item/handheld",
    textures = { layer0 = "minecraft:item/iron_pickaxe" } }) == "minecraft:item/iron_pickaxe")

-- icons runtime: ленивый кэш + LRU + free при вытеснении
do
  local icons = require("icons")
  local freed = {}
  local fetched = {}
  -- мок http/fs/decode через DI
  icons.configure({
    baseUrl = "http://x/", dir = "/icons", limit = 2,
    exists = function(_) return false end,
    fetch = function(url) fetched[#fetched + 1] = url; return "PNGBYTES:" .. url end,
    decode = function(bytes) return { bytes = bytes, free = function(self) freed[#freed + 1] = self.bytes end } end,
  })
  local a = icons.get("create:cogwheel")
  check("icons.get: декодировал и вернул ref", a ~= nil and a.bytes:find("create__cogwheel.png", 1, true) ~= nil)
  local a2 = icons.get("create:cogwheel")
  check("icons.get: второй вызов из кэша (один fetch)", a2 == a and #fetched == 1)
  icons.get("minecraft:iron_ingot")  -- кэш = 2
  icons.get("minecraft:redstone")    -- лимит 2 → вытеснение самого старого (cogwheel)
  check("icons.get: LRU вытеснил и вызвал free", #freed == 1 and freed[1]:find("cogwheel", 1, true) ~= nil)
  check("icons.cacheCount: держит лимит", icons.cacheCount() == 2)
end

-- layoutPx: пиксельная раскладка GPU (зоны не пересекаются, грид непустой)
do
  local ui = require("ui_logic")
  local P = ui.layoutPx(328, 200)
  check("layoutPx: title сверху (y1=1)", P.title.y1 == 1)
  check("layoutPx: cart слева от грида (cart.x2 < grid.x1)", P.cart.x2 < P.grid.x1)
  check("layoutPx: грид выше кнопок (grid.y2 < btns.y1)", P.grid.y2 < P.btns.y1)
  check("layoutPx: кнопки в самом низу (btns.y2 == h)", P.btns.y2 == 200)
  check("layoutPx: грид шире одной плитки (>=60px)", (P.grid.x2 - P.grid.x1 + 1) >= 60)
  check("layoutPx: cart имеет свою прокрутку (cartUp выше cartDown)",
    P.cartUp.y2 < P.cartDown.y1)
  check("layoutPx: scroll-колонка правее грида (scroll.x1 > grid.x2)",
    P.scroll.x1 > P.grid.x2)
end
-- nextStep4: цикл 1/16/32/64
check("nextStep4 1->16->32->64->1", (function()
  local u = require("ui_logic")
  return u.nextStep4(1) == 16 and u.nextStep4(16) == 32
     and u.nextStep4(32) == 64 and u.nextStep4(64) == 1
end)())

-- render_text backend methods (perPage / defaultStep / nextStep)
local render_text = require("render_text")
local function fakeSurface(w, h)
  return { getSize = function() return w, h end }
end
do
  local ui = require("ui_logic")
  local L = ui.layout(50, 19)
  local expect = ui.gridDims(L.grid, 12, 6, 1).perPage
  check("render_text.perPage = gridDims.perPage по getSize",
    render_text.perPage(fakeSurface(50, 19)) == expect)
end
check("render_text.defaultStep = 1", render_text.defaultStep == 1)
check("render_text.nextStep 1->8->64->1",
  render_text.nextStep(1) == 8 and render_text.nextStep(8) == 64 and render_text.nextStep(64) == 1)

-- render_gpu backend basics
do
  package.path = "./test/?.lua;" .. package.path
  local mockgpu = require("mock-gpu")
  local rg = require("render_gpu")
  local ui = require("ui_logic")
  check("render_gpu.defaultStep = 32", rg.defaultStep == 32)
  check("render_gpu.nextStep = nextStep4",
    rg.nextStep(1) == 16 and rg.nextStep(64) == 1)
  local g = mockgpu.new(328, 200)
  local P = ui.layoutPx(328, 200)
  local expect = ui.gridDims(P.grid, 56, 44, 4).perPage
  check("render_gpu.perPage = gridDims(layoutPx) по getSize",
    rg.perPage(g) == expect)
  check("render_gpu.applyPalette не падает (full-color no-op)",
    (function() rg.applyPalette(g); return true end)())
end

-- render_gpu.draw produces tiles + hit zones + calls the GPU
do
  local mockgpu = require("mock-gpu")
  local rg = require("render_gpu")
  local ui = require("ui_logic")
  local g = mockgpu.new(328, 200)
  local model = {
    items = {
      { id = "create:cogwheel", display = "Cogwheel", count = 128, group = "Create" },
      { id = "minecraft:iron_ingot", display = "Iron Ingot", count = 512, group = "Resources" },
    },
    groups = { "All", "Create", "Resources" }, group = "All",
    query = "", searchFocus = false, scroll = 0,
    address = "Main", basket = ui.basketNew(), step = 32, toast = nil,
  }
  ui.basketAdd(model.basket, model.items[1], 32)
  local hit = rg.draw(g, model)
  check("gpu.draw: вернул плитки (2 items)", #hit.tiles == 2)
  check("gpu.draw: плитка несёт entry", hit.tiles[1].entry.id == "create:cogwheel")
  check("gpu.draw: есть search/addr хит-зоны", hit.search ~= nil and hit.addr ~= nil)
  check("gpu.draw: есть step-кнопка", hit.step ~= nil)
  check("gpu.draw: confirm появился (корзина непуста)", hit.confirm ~= nil)
  check("gpu.draw: рисовал на GPU (filledRectangle вызван)",
    (function() for _, c in ipairs(g._calls) do if c.op == "filledRectangle" then return true end end return false end)())
  check("gpu.draw: писал текст имени предмета",
    (function() for _, c in ipairs(g._calls) do if c.op == "drawText" and c.s and c.s:find("Cogwheel", 1, true) then return true end end return false end)())
end

-- render_gpu: использует реальную иконку, когда icons.get отдаёт ref
do
  local mockgpu = require("mock-gpu")
  local icons = require("icons")
  local rg = require("render_gpu")
  local ui = require("ui_logic")
  local g = mockgpu.new(328, 200)
  -- icons настроен отдавать ref для всех id (фейк-байты)
  icons.configure({
    baseUrl = "http://x/", dir = "/icons", limit = 8,
    fetch = function(url) return "BYTES" end,
    decode = function(bytes) return g.decodeImage(bytes) end,
  })
  rg.useIcons(icons)  -- инъекция icons-модуля в рендер
  local model = {
    items = { { id = "create:cogwheel", display = "Cogwheel", count = 128, group = "Create" } },
    groups = { "All" }, group = "All", query = "", searchFocus = false, scroll = 0,
    address = "Main", basket = ui.basketNew(), step = 32,
  }
  rg.draw(g, model)
  check("gpu.draw: вызвал drawImage для реальной иконки",
    (function() for _, c in ipairs(g._calls) do if c.op == "drawImage" then return true end end return false end)())
end
-- и фолбэк: без icons рисует глиф (filledRectangle), не падает
do
  local mockgpu = require("mock-gpu")
  local rg = require("render_gpu")
  local ui = require("ui_logic")
  rg.useIcons(nil)
  local g = mockgpu.new(328, 200)
  local model = {
    items = { { id = "create:weird_block", display = "Weird", count = 1, group = "Create" } },
    groups = { "All" }, group = "All", query = "", searchFocus = false, scroll = 0,
    address = "Main", basket = ui.basketNew(), step = 32,
  }
  check("gpu.draw без icons не падает", (function() rg.draw(g, model); return true end)())
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
