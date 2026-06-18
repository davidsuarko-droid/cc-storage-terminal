# Handoff — cc-storage-terminal

Дата: 2026-06-18

## Состояние
Свежий репо. Спек + план перенесены в `docs/`. Идёт реализация по `docs/plan.md` (8 задач, TDD).

## Сделано
- Репо `cc-storage-terminal` создан (private), git init, remote, .gitignore.
- Lua 5.1.5 собран локально → `~/.local/bin/lua5.1`.
- Спек (`docs/spec.md`) + план (`docs/plan.md`).

## Дальше
Task 1 → Task 8 по `docs/plan.md`. Пути в плане были `scripts/cc-tweaked/storage-terminal/` —
в этом репо: модули в `src/`, тесты в `test/`. `spec.lua` ищет модули в `./src/?.lua`.

## Не сделано
- Код модулей (всё впереди).
- CraftOS-PC не установлен (Task 8 smoke).
- In-game проверка.
- Скилл «Lua в Minecraft с моими условиями» — отложен (попросил позже).
