-- Сетевой протокол server<->pocket поверх rednet. Чистые строители сообщений
-- (тестируемы) + тонкие I/O-обёртки над rednet/peripheral.
local M = {}

M.PROTO = "ccstore"

-- === чистые строители/валидаторы сообщений ===

function M.reqStock()
  return { t = "stock" }
end

-- ответ на запрос стока: список товаров + адреса доставки
function M.respStock(items, addresses)
  return { t = "stock", items = items or {}, addresses = addresses or {} }
end

function M.reqOrder(id, qty, address)
  return { t = "order", id = id, qty = qty, address = address }
end

function M.respOrder(got)
  return { t = "order", got = got or 0 }
end

-- тип сообщения или nil, если это не наш кадр
function M.kind(msg)
  if type(msg) ~= "table" then return nil end
  return msg.t
end

-- === I/O: открыть rednet на первом модеме (или заданной стороне) ===

function M.open(side)
  if side then
    rednet.open(side)
    return side
  end
  for _, s in ipairs(rs.getSides()) do
    if peripheral.getType(s) == "modem" then
      rednet.open(s)
      return s
    end
  end
  error("Не найден модем. Подключи Wireless Modem (или ender-модем).", 0)
end

return M
