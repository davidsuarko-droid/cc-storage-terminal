-- Конфиг терминала. Стороны nil = авто-детект периферии по типу.
local config = {
  REFRESH      = 2,   -- секунды между обновлениями стока
  TICKER_SIDE  = nil, -- напр. "back" чтобы форсить сторону тикера
  MONITOR_SIDE = nil, -- напр. "left" чтобы форсить сторону монитора
  MODEM_SIDE   = nil, -- напр. "top" чтобы форсить сторону модема (rednet)
}
return config
