-- Список адресов доставки пакетной сети Create.
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
