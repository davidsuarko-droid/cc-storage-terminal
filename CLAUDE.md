# CLAUDE.md — cc-storage-terminal

Сенсорный терминал-маркетплейс на **CC:Tweaked** (ComputerCraft, Minecraft) над **Create 6 Stock Ticker**.
Смотреть остатки всей базы, искать/листать по категориям, заказывать N штук на адрес (`Main`/`Core`).

## Стек / диалект
- **Lua 5.1** (CC = Cobalt ≈ 5.1). Никакого синтаксиса 5.2+ (`goto`, целочисл. деление).
- Целевая периферия: `Create_StockTicker` (методы `stock`, `requestFiltered`).
- Монитор: тип `monitor` (advanced). Тач + цвет.

## Структура
- `src/` — модули (`config`, `names`, `addresses`, `classify`, `stock`, `ui_logic`, `order`, `peripherals`, `sprites`, `render`, `startup`).
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
Расстановка: справа компа — Stock Ticker, сзади — склад, слева — Advanced Monitor (стороны не важны, авто-детект по типу).
Перенос: `pastebin`/`wget` по файлам либо копия в `world/computercraft/computer/<id>/`. `startup.lua` = автозапуск.

## Принципы
- Чистая логика (фильтры, нормализация, хит-тест) отделена от I/O (рендер, периферии, циклы) → юнит-тестируема.
- TDD: тест → падение → реализация → зелёный → коммит.
- Каждый модуль `return M`; единственный `main()`-слой — `startup.lua`.

## Handoff
См. `handoff.md` в корне — текущее состояние, что сделано, что дальше.
