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
check("layout: cats слева ширина 14", Lay.cats.x2 == 14)
check("layout: grid правее cats (x1=15)", Lay.grid.x1 == 15)
check("layout: status снизу (y2=h)", Lay.status.y2 == 19)

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

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
