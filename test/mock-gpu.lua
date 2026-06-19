-- Стаб Tom's Peripherals GPU для headless-тестов. Пишет каждый вызов в _calls,
-- decodeImage возвращает фейковый image-ref с .free(). Ничего не рисует.
local M = {}

function M.new(w, h)
  w = w or 328; h = h or 200
  local calls = {}
  local nextId = 0
  local function rec(op, t) t = t or {}; t.op = op; calls[#calls + 1] = t; return t end
  local gpu = { _calls = calls, _images = {} }
  function gpu.getSize() return w, h end
  function gpu.refreshSize() rec("refreshSize") end
  function gpu.setSize(res) rec("setSize", { res = res }) end
  function gpu.fill(c) rec("fill", { c = c }) end
  function gpu.filledRectangle(x, y, ww, hh, c) rec("filledRectangle", { x = x, y = y, w = ww, h = hh, c = c }) end
  function gpu.rectangle(x, y, ww, hh, c) rec("rectangle", { x = x, y = y, w = ww, h = hh, c = c }) end
  function gpu.drawText(x, y, s, fg, bg, size, pad) rec("drawText", { x = x, y = y, s = s, fg = fg, bg = bg, size = size, pad = pad }) end
  function gpu.drawImage(x, y, ref) rec("drawImage", { x = x, y = y, ref = ref }) end
  function gpu.decodeImage(bytes)
    nextId = nextId + 1
    local id = nextId
    rec("decodeImage", { id = id, len = bytes and #bytes or 0 })
    local ref = { _id = id, free = function() rec("free", { id = id }) end }
    gpu._images[#gpu._images + 1] = ref
    return ref
  end
  function gpu.newImage(ww, hh) nextId = nextId + 1; return { _id = nextId, w = ww, h = hh } end
  function gpu.imageFromBuffer() nextId = nextId + 1; return { _id = nextId } end
  function gpu.sync() rec("sync") end
  return gpu
end

return M
