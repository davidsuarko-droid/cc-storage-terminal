-- Прогон installer.lua в хост-Lua: мок CC fs/term, распаковка в tmp-каталог,
-- затем loadfile каждого распакованного .lua. Аргумент: путь tmp-каталога.
local tmp = assert(arg[1], "нужен путь tmp-каталога")
local realio = io
fs = {
  exists = function(p)
    local f = realio.open(tmp .. "/" .. p); if f then f:close(); return true end; return false
  end,
  open = function(p, mode)
    local f = assert(realio.open(tmp .. "/" .. p, mode:find("w") and "w" or "r"))
    return {
      write = function(s) f:write(s) end,
      writeLine = function(s) f:write(s .. "\n") end,
      readAll = function() return f:read("*a") end,
      close = function() f:close() end,
    }
  end,
}
term = { setTextColor = function() end, write = function() end }
colors = setmetatable({}, { __index = function(_, k) return k end })
local realprint = print
print = function() end
dofile("installer.lua")
print = realprint
