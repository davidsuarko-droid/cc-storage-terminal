# CLAUDE.md — cc-storage-terminal

Сенсорный терминал-маркетплейс на **CC:Tweaked** (ComputerCraft, Minecraft) над **Create 6 Stock Ticker**.
Смотреть остатки всей базы, искать/листать по категориям, заказывать N штук на адрес (`Main`/`Core`).

## Стек / диалект
- **Lua 5.1** (CC = Cobalt ≈ 5.1). Никакого синтаксиса 5.2+ (`goto`, целочисл. деление).
- Целевая периферия: `Create_StockTicker` (методы `stock`, `requestFiltered`).
- Монитор: тип `monitor` (advanced). Тач + цвет.

## Структура
- `src/` — модули (`config`, `names`, `addresses`, `classify`, `stock`, `ui_logic`, `order`, `peripherals`, `sprites`, `render`, `net`, `server`, `pocket`, `startup`).
- `startup.lua` = диспетчер: глобал `pocket` есть → клиент (`pocket.lua`), иначе сервер (`server.lua`).
- **Сервер** (стационарный): тикер + монитор + модем, тач-заказ + раздача стока/заказов по rednet (`net.lua`, протокол `ccstore`).
- **Покет** (advanced pocket): тянет сток у сервера, рисует на `term`, заказ мышью (ЛКМ=стак, ПКМ=1шт, колесо над плиткой=±шаг).
- `test/` — `mock-cc.lua` (стабы CC) + `spec.lua` (юниты) + `smoke.lua` + `render-preview.lua` (глаз-чек).
- `scripts/gen-installer.lua` — перегенерация `installer.lua` из `src/*.lua` + `*.cfg`.
- `docs/spec.md`, `docs/plan.md` — дизайн + план реализации.
- `*.cfg` — редактируемые в игре: `names.cfg` (id→ярлык), `addresses.cfg` (адреса доставки).

## Тесты
```bash
lua5.1 test/spec.lua    # юниты (хост-Lua 5.1.5 → ~/.local/bin/lua5.1)
lua5.1 test/smoke.lua   # startup грузится, периферия валидируется
```
Бинарь Lua собран локально: `~/.local/bin/lua5.1`. PATH: `export PATH="$HOME/.local/bin:$PATH"`.

## Деплой в игру
Сервер: рядом с компом — Stock Ticker, склад, Advanced Monitor, **Wireless/Ender Modem** (стороны не важны, авто-детект по типу; ender-модем = бесконечная дальность).
Покет: Advanced Pocket Computer со встроенным wireless-модемом (крафт с ender pearl = ender-дальность).
Установка обоих: `wget run <raw installer url>` → один и тот же бандл, `startup.lua` сам определяет устройство. Перенос альтернативой: копия в `world/computercraft/computer/<id>/`.

## Принципы
- Чистая логика (фильтры, нормализация, хит-тест) отделена от I/O (рендер, периферии, циклы) → юнит-тестируема.
- TDD: тест → падение → реализация → зелёный → коммит.
- Каждый модуль `return M`; единственный `main()`-слой — `startup.lua`.

## Handoff
См. `handoff.md` в корне — текущее состояние, что сделано, что дальше.
