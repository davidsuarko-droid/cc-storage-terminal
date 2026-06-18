-- Генератор installer.lua: бандлит src/*.lua + *.cfg в один самодостаточный файл.
-- Запуск из корня репо: lua5.1 scripts/gen-installer.lua
-- .cfg пишутся в корень компа только если ещё нет (правки в игре не затираются).

local SRC = "src"
local CFG = { "names.cfg", "addresses.cfg" }

local function read(path)
  local h = assert(io.open(path, "r"), "no file: " .. path)
  local s = h:read("*a"); h:close(); return s
end

-- список .lua в src (без рекурсии), по алфавиту
local function listLua()
  local out = {}
  local p = io.popen('ls "' .. SRC .. '"')
  for line in p:lines() do
    if line:match("%.lua$") then out[#out + 1] = line end
  end
  p:close()
  table.sort(out)
  return out
end

-- выбрать уровень длинных скобок [=...=[ так, чтобы тело не коллизило
local function bracket(body)
  for n = 1, 8 do
    local eq = string.rep("=", n)
    if not body:find("]" .. eq .. "]", 1, true) then return "[" .. eq .. "[", "]" .. eq .. "]" end
  end
  error("не подобрать уровень скобок")
end

local parts = {}
parts[#parts + 1] = "-- cc-storage-terminal installer. Run: wget run <url>"
parts[#parts + 1] = "-- СГЕНЕРИРОВАНО scripts/gen-installer.lua — не править вручную."
parts[#parts + 1] = "-- Пишет все модули плоско в корень компа."
parts[#parts + 1] = "local F = {}"

local function emit(name, body)
  local ob, cb = bracket(body)
  -- ведущий перевод строки после [=[ съедается Lua — добавляем сами для читаемости
  parts[#parts + 1] = 'F["' .. name .. '"] = ' .. ob .. "\n" .. body .. cb
end

for _, f in ipairs(listLua()) do emit(f, read(SRC .. "/" .. f)) end
for _, c in ipairs(CFG) do emit(c, read(c)) end

parts[#parts + 1] = [[
for name, body in pairs(F) do
  if name:match("%.cfg$") and fs.exists(name) then
    print("skip "..name.." (есть)")
  else
    local h = fs.open(name, "w"); h.write(body); h.close()
    print("write "..name)
  end
end
print("Готово. Ребут или: startup")]]

local out = io.open("installer.lua", "w")
out:write(table.concat(parts, "\n"))
out:close()
print("installer.lua сгенерирован (" .. #listLua() .. " lua + " .. #CFG .. " cfg)")
