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

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
