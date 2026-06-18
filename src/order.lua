-- Размещение заказа на адрес пакетной сети.
local M = {}

function M.place(ticker, id, qty, address)
  return ticker.requestFiltered(address, { name = id, _requestCount = qty })
end

return M
