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

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
