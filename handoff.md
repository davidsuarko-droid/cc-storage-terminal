# Handoff — cc-storage-terminal

Дата: 2026-06-18

## Состояние
MVP + редизайн готовы, запушены в `origin/main`. 67 юнит-тестов зелёные, smoke + render-preview зелёные.
Деплой в игре: `wget run https://raw.githubusercontent.com/davidsuarko-droid/cc-storage-terminal/main/installer.lua`

## Редизайн (2026-06-18)
- `classify.lua` — таксономия Create→Redstone→Resources→Wood→Stone→Building→Other (tags+id).
- `render.lua` — DESIGN.md стиль: near-black/белый, синий точечно, чередование строк,
  count right-align, beveled keypad, скролл `[^]`/`[v]`, **English ASCII** (CC-шрифт без кириллицы).
- `ui_logic.layout` новый (title/search/cats/grid/scroll/status) + `page()`.
- Глаз-чек раскладки: `lua5.1 test/render-preview.lua [W H]`.

## Сделано
- Репо `cc-storage-terminal` (private), git, push в main.
- Lua 5.1.5 локально → `~/.local/bin/lua5.1`.
- Модули `src/`: config, names, addresses, stock, ui_logic, order, peripherals, render, startup.
- Тесты `test/`: spec.lua (41 ✓), smoke.lua (✓), mock-cc.lua.
- Конфиги: `names.cfg`, `addresses.cfg` (Main, Core).
- Спек/план в `docs/`.

## Дальше — in-game проверка (за пользователем)
Расстановка: справа компа — Stock Ticker, сзади — склад, слева — Advanced Monitor.
Деплой: скопировать `src/*.lua` + `*.cfg` **плоско** в корень компа (`startup.lua` = автозапуск),
либо `pastebin`/`wget` по файлам, либо в `world/computercraft/computer/<id>/`. Ребут.

Чек-лист:
1. Грузится: поиск + категории + сетка + полоса адреса.
2. Остатки обновляются ~2с.
3. Тап по категории фильтрует.
4. Тап по полю поиска → фокус (жёлтый); печать на клаве фильтрует живьём; backspace стирает; enter снимает фокус.
5. Тап по полосе адреса переключает Main↔Core.
6. Тап по предмету → кейпад; набрать число, OK → тост «Заказано Nx… -> <адрес>», посылка в адрес.

## Опционал / отложено
- CraftOS-PC headless smoke — не ставился (sudo/snap упирались); хост-Lua smoke уже подтверждает загрузку.
- Скилл «Lua в Minecraft с моими условиями» — попросил позже.
- SP2 (DPS-трекер) / SP3 (цепочка крафта) — отдельные под-проекты, в спеке отложены.

## Заметки реализации
- Все модули `return M`; единственный main-слой — `startup.lua`.
- Чистая логика (`ui_logic`, `stock`, `names`, `addresses`, `order`) юнит-тестируема без CC.
- Периферии авто-детект по типу (`Create_StockTicker`, `monitor`/`monitor_advanced`), override стороной в `config.lua`.
- Деплой кладёт файлы плоско → `require("config")` и т.п. резолвится из корня компа.
