# GPU Render Pivot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the server-side storage marketplace on a Tom's Peripherals GPU monitor with real pixel tiles, full item names, real item icons, and a scrollable cart — while keeping the pocket client and GPU-less servers on the existing text renderer.

**Architecture:** Split the draw layer behind a uniform backend interface (`applyPalette`, `draw`, `perPage`, `defaultStep`, `nextStep`). `ui_logic.lua` stays pure and shared (layout/tiles/basket/filter/page) and gains a parallel `layoutPx` for the pixel grid. `server.lua` picks `render_gpu` when `peripheral.find("tm_gpu")` succeeds, otherwise `render_text` (the renamed `render.lua`). Icons are extracted offline from modpack jars into committed PNGs and lazily fetched at runtime, decoded by the GPU's `decodeImage`, cached LRU.

**Tech Stack:** Lua 5.1 (CC:Tweaked / Cobalt — no 5.2+ syntax), Tom's Peripherals GPU (`tm_gpu`), Python 3 (offline icon extraction only), host test binary `~/.local/bin/lua5.1`.

## Global Constraints

- **Lua 5.1 only** — no `goto`, no integer division `//`, no 5.2+ syntax. CC = Cobalt ≈ 5.1.
- **On-screen chrome is English ASCII only** — CC font has no Cyrillic. Code comments stay Russian/caveman as in the existing files.
- **Each module ends with `return M`**; the only `main()`-layer is `startup.lua`.
- **Pure logic stays in `ui_logic.lua`** (no I/O); rendering and peripherals stay out of it.
- **Test binary:** `~/.local/bin/lua5.1` — `export PATH="$HOME/.local/bin:$PATH"` first.
- **Backwards compatibility:** a server with no `tm_gpu` must behave exactly as today (text renderer on the CC monitor). Old installs must not break.
- **Commit messages:** Conventional commits, end every commit body with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- **Never** `--no-verify` or `--force` on `main` without explicit permission.
- **GPU increments:** normal tap = `+model.step` (GPU default step 32), sneak+tap = `+16` fixed, Step button cycles `1 → 16 → 32 → 64 → 1`. Text backend default step 1, Step cycles `1 → 8 → 64`.

---

## File Structure

| File | Responsibility | Phase |
|------|----------------|-------|
| `src/render_text.lua` | Renamed from `render.lua`. Char/symbolic CC renderer. Pocket + GPU-less server fallback. Gains `perPage`/`defaultStep`/`nextStep`. | 1 |
| `src/server.lua` | Picks backend by `tm_gpu`, routes both `monitor_touch` and `tm_monitor_touch`, sneak-aware increments. | 1 |
| `src/pocket.lua` | Requires `render_text` (was `render`). | 1 |
| `src/ui_logic.lua` | Adds `layoutPx(wpx,hpx)` and `nextStep4(step)`. Everything else unchanged. | 2 |
| `src/render_gpu.lua` | NEW. Tom's GPU pixel renderer: tiles, big names, cart panel w/ own scroll, buttons, category pixel icons. | 2 |
| `test/mock-gpu.lua` | NEW. Stub `tm_gpu` (filledRectangle/rectangle/line/drawText/drawImage/decodeImage/getSize/sync) recording calls. | 2 |
| `test/preview-gpu.lua` | NEW. Eye-check dump of GPU draw calls. | 2 |
| `src/icons.lua` | NEW. Pure `idToFile`, `parseLayer0`, plus runtime lazy-load + LRU cache + `decodeImage`. | 3 |
| `scripts/build-icons.py` | NEW. Offline: jar → item model → `layer0` PNG → `icons/<ns>__<name>.png` + `manifest.txt`. | 3 |
| `icons/` | NEW. Committed PNGs + `manifest.txt`. | 3 |
| `test/spec.lua` | Add units for `perPage`, `layoutPx`, `nextStep4`, `idToFile`, `parseLayer0`, LRU. | 1–3 |
| `CLAUDE.md` | Update module list. | 1 |
| `installer.lua` | Regenerated each phase via `scripts/gen-installer.lua` (auto-picks `src/*.lua`). | 1–4 |

---

## Phase 1 — Backend split + `tm_gpu` detect (fallback preserved)

### Task 1.1: Rename `render.lua` → `render_text.lua`, add backend methods

**Files:**
- Create (via rename): `src/render_text.lua` (from `src/render.lua`)
- Modify: `test/spec.lua` (add `perPage`/`defaultStep`/`nextStep` units)

**Interfaces:**
- Produces: `render_text.applyPalette(surface)`, `render_text.draw(surface, model) -> hit`, `render_text.perPage(surface) -> number`, `render_text.defaultStep = 1`, `render_text.nextStep(step) -> number`.

- [ ] **Step 1: Write the failing test**

Add to `test/spec.lua` (after the existing render-independent units, before the summary print):

```lua
-- render_text backend methods (perPage / defaultStep / nextStep)
local render_text = require("render_text")
local function fakeSurface(w, h)
  return { getSize = function() return w, h end }
end
do
  local ui = require("ui_logic")
  local L = ui.layout(50, 19)
  local expect = ui.gridDims(L.grid, 12, 6, 1).perPage
  check("render_text.perPage = gridDims.perPage по getSize",
    render_text.perPage(fakeSurface(50, 19)) == expect)
end
check("render_text.defaultStep = 1", render_text.defaultStep == 1)
check("render_text.nextStep 1->8->64->1",
  render_text.nextStep(1) == 8 and render_text.nextStep(8) == 64 and render_text.nextStep(64) == 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/davidadmin/claudeproject/projects/cc-storage-terminal && ~/.local/bin/lua5.1 test/spec.lua`
Expected: FAIL — `module 'render_text' not found` (file still named `render.lua`).

- [ ] **Step 3: Rename the file and add the methods**

```bash
cd /home/davidadmin/claudeproject/projects/cc-storage-terminal
git mv src/render.lua src/render_text.lua
```

Then append the three methods to `src/render_text.lua`, immediately before the final `return M` line:

```lua
-- === Backend-интерфейс (общий с render_gpu) ===
M.defaultStep = 1

-- Цикл шага накопления для тач-монитора: 1 → 8 → 64 → 1.
function M.nextStep(step)
  return ui_logic.nextStep(step)
end

-- Сколько плиток на странице при текущем размере поверхности (символы).
function M.perPage(surface)
  local w, h = surface.getSize()
  local L = ui_logic.layout(w, h)
  return ui_logic.gridDims(L.grid, 12, 6, 1).perPage
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: PASS — all `render_text.*` checks `ok`, 0 FAIL.

- [ ] **Step 5: Commit**

```bash
git add src/render_text.lua test/spec.lua
git commit -m "$(cat <<'EOF'
refactor: rename render.lua to render_text.lua + backend methods

perPage/defaultStep/nextStep form the shared backend interface so
server.lua can swap renderers without knowing which is active.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

### Task 1.2: Point `pocket.lua` and `server.lua` at the renamed module + backend pick

**Files:**
- Modify: `src/pocket.lua:7` (require), `src/pocket.lua:13` (applyPalette), `src/pocket.lua:38-39` (draw)
- Modify: `src/server.lua:10,21-23,43-47,60-62` (require, backend pick, perPage, redraw)
- Test: `test/smoke.lua` (already covers load; no change unless it fails)

**Interfaces:**
- Consumes: `render_text.{applyPalette,draw,perPage,defaultStep,nextStep}`.
- Produces: `server.lua` local `backend` + `surface`; touch handler signature `handleTouch(x, y, sneaking)`.

- [ ] **Step 1: Run smoke to capture current green baseline**

Run: `~/.local/bin/lua5.1 test/smoke.lua`
Expected: currently FAIL — `module 'render' not found` (pocket/server still require the old name). This is the failing state Task 1.2 fixes.

- [ ] **Step 2: Update `pocket.lua`**

In `src/pocket.lua` change the require line:

```lua
local render   = require("render_text")
```

(Keep the local variable name `render` so lines 13/38-39 — `render.applyPalette(term)` and `render.draw(term, model)` — stay valid. Only the required module name changes.)

- [ ] **Step 3: Update `server.lua` — backend selection**

Replace `src/server.lua` line 10:

```lua
local render_text = require("render_text")
```

Replace lines 21-23 (the `peripherals.find` + `applyPalette` + `net.open` block) with:

```lua
local ticker, monitor = peripherals.find(config)
-- Бэкенд рендера: есть Tom's GPU → пиксельный render_gpu на его мониторе;
-- нет → символьный render_text на CC-мониторе (старое поведение).
local backend, surface
local gpu = peripheral.find("tm_gpu")
if gpu then
  backend = require("render_gpu")
  surface = gpu
else
  backend = render_text
  surface = monitor
end
backend.applyPalette(surface)
local modemSide = net.open(config.MODEM_SIDE) -- nil = модема нет, работаем как монитор без раздачи
```

Replace `gridPerPage` (lines 43-47) with a backend delegation:

```lua
local function gridPerPage()
  return backend.perPage(surface)
end
```

Replace `redraw` (lines 60-62):

```lua
local function redraw()
  hit = backend.draw(surface, model)
end
```

In the `model` table (lines 27-33) set the initial step from the backend:

```lua
  basket = ui_logic.basketNew(), step = render_text.defaultStep,
```

Then immediately after the `backend`/`surface` block above, fix the step to the chosen backend (default differs for GPU):

```lua
-- step по умолчанию зависит от бэкенда (GPU = полстака)
```

(Apply by changing the `model.step` initializer to `backend.defaultStep` instead of a literal — do this in the `model = { ... }` table since `backend` is now defined above it. Concretely the basket line becomes:)

```lua
  basket = ui_logic.basketNew(), step = backend.defaultStep,
```

- [ ] **Step 4: Update `server.lua` — sneak-aware touch + tm_monitor_touch**

Change `handleTouch` signature and the tile branch. Replace the function header (line 72):

```lua
local function handleTouch(x, y, sneaking)
```

Replace the tile loop at the end of `handleTouch` (lines 120-126):

```lua
  for _, it in ipairs(hit.tiles or {}) do
    if ui_logic.inside(it.rect, x, y) then
      local delta = sneaking and 16 or model.step
      ui_logic.basketAdd(model.basket, it.entry, delta)
      model.pressed = it.entry.id
      return
    end
  end
```

In `inputLoop` replace the `monitor_touch` branch (lines 133-135) to handle both event types:

```lua
    if name == "monitor_touch" then
      handleTouch(ev[3], ev[4])
      redraw()
    elseif name == "tm_monitor_touch" then
      handleTouch(ev[2], ev[3], ev[4]) -- (x, y, sneaking)
      redraw()
```

(Note: `tm_monitor_touch` params are `(x, y, sneaking)` at `ev[2..4]`; vanilla `monitor_touch` is `(side, x, y)` at `ev[2..4]`, so x/y are `ev[3],ev[4]`.)

Replace the Step handler (lines 92-95) to use the backend cycle:

```lua
  if hit.step and ui_logic.inside(hit.step, x, y) then
    model.step = backend.nextStep(model.step)
    return
  end
```

- [ ] **Step 5: Run smoke + spec to verify green**

Run: `~/.local/bin/lua5.1 test/smoke.lua && ~/.local/bin/lua5.1 test/spec.lua`
Expected: smoke prints `smoke OK`; spec 0 FAIL. (No `tm_gpu` in mock → `render_gpu` is never required in tests, so its absence this phase is fine.)

- [ ] **Step 6: Commit**

```bash
git add src/server.lua src/pocket.lua
git commit -m "$(cat <<'EOF'
feat: select render backend by tm_gpu, route tm_monitor_touch

Server picks render_gpu when a Tom's Peripherals GPU is attached,
else falls back to render_text on the CC monitor (unchanged behavior).
Sneak+tap adds +16; Step cycle and per-page paging delegate to backend.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

### Task 1.3: Update docs + regenerate installer

**Files:**
- Modify: `CLAUDE.md:12` (module list)
- Regenerate: `installer.lua`

- [ ] **Step 1: Update the module list in `CLAUDE.md`**

Replace the `src/` bullet (line 12) so `render` becomes `render_text`, `render_gpu`:

```markdown
- `src/` — модули (`config`, `names`, `addresses`, `classify`, `stock`, `ui_logic`, `order`, `peripherals`, `sprites`, `render_text`, `render_gpu`, `icons`, `net`, `server`, `pocket`, `startup`).
```

- [ ] **Step 2: Regenerate the installer**

Run: `cd /home/davidadmin/claudeproject/projects/cc-storage-terminal && ~/.local/bin/lua5.1 scripts/gen-installer.lua`
Expected: prints `installer.lua сгенерирован (N lua + 2 cfg)` with the renamed module included.

- [ ] **Step 3: Sanity-load the installer**

Run: `~/.local/bin/lua5.1 -e 'assert(loadfile("installer.lua"))' && echo OK`
Expected: `OK` (parses; it won't run without CC `fs`).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md installer.lua
git commit -m "$(cat <<'EOF'
chore: regen installer + doc render backend split

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — `render_gpu.lua` with category icons (no real textures yet)

### Task 2.1: `ui_logic.layoutPx` + `nextStep4` (pure)

**Files:**
- Modify: `src/ui_logic.lua` (add `M.layoutPx`, `M.nextStep4`)
- Test: `test/spec.lua`

**Interfaces:**
- Produces: `ui_logic.layoutPx(w, h) -> { title, search, chips, grid, cart, scroll, up, down, status, btns, cartScroll, cartUp, cartDown }` (pixel rects, same `{x1,y1,x2,y2}` shape as `layout`); `ui_logic.nextStep4(step) -> number` cycling `1→16→32→64→1`.
- Consumed by: `render_gpu.draw`, `render_gpu.perPage`, `render_gpu.nextStep`.

- [ ] **Step 1: Write the failing test**

Add to `test/spec.lua`:

```lua
-- layoutPx: пиксельная раскладка GPU (зоны не пересекаются, грид непустой)
do
  local ui = require("ui_logic")
  local P = ui.layoutPx(328, 200)
  check("layoutPx: title сверху (y1=1)", P.title.y1 == 1)
  check("layoutPx: cart слева от грида (cart.x2 < grid.x1)", P.cart.x2 < P.grid.x1)
  check("layoutPx: грид выше кнопок (grid.y2 < btns.y1)", P.grid.y2 < P.btns.y1)
  check("layoutPx: кнопки в самом низу (btns.y2 == h)", P.btns.y2 == 200)
  check("layoutPx: грид шире одной плитки (>=60px)", (P.grid.x2 - P.grid.x1 + 1) >= 60)
  check("layoutPx: cart имеет свою прокрутку (cartUp выше cartDown)",
    P.cartUp.y2 < P.cartDown.y1)
  check("layoutPx: scroll-колонка правее грида (scroll.x1 > grid.x2)",
    P.scroll.x1 > P.grid.x2)
end
-- nextStep4: цикл 1/16/32/64
check("nextStep4 1->16->32->64->1", (function()
  local u = require("ui_logic")
  return u.nextStep4(1) == 16 and u.nextStep4(16) == 32
     and u.nextStep4(32) == 64 and u.nextStep4(64) == 1
end)())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: FAIL — `attempt to call field 'layoutPx' (a nil value)`.

- [ ] **Step 3: Implement `layoutPx` + `nextStep4` in `ui_logic.lua`**

Insert before the final `return M` (after `M.layout`):

```lua
-- Пиксельная раскладка для GPU-монитора (Tom's Peripherals).
-- Та же структура зон, что layout, но в пикселях и с крупными плитками.
-- Слева — постоянная корзина со своей прокруткой; справа — грид; внизу — кнопки.
function M.layoutPx(w, h)
  local pad     = 4
  local titleH  = 18
  local searchH = 16
  local chipsH  = 20
  local btnH    = 22
  local statusH = 14
  local scrollW = 22                                  -- колонка стрелок грида справа
  local cartW   = math.max(96, math.floor(w * 0.30))  -- левая панель корзины
  local headY   = 1
  local searchY = headY + titleH
  local chipsY  = searchY + searchH
  local bodyTop = chipsY + chipsH + pad
  local btnY    = h - btnH + 1
  local statusY = btnY - statusH
  local bodyBot = statusY - pad
  local gridX1  = cartW + pad + 1
  local gridX2  = w - scrollW - pad
  return {
    title  = { x1 = 1,            y1 = headY,   x2 = w,           y2 = headY + titleH - 1 },
    addr   = { x1 = w - 140 + 1,  y1 = headY,   x2 = w,           y2 = headY + titleH - 1 },
    search = { x1 = 1,            y1 = searchY, x2 = w,           y2 = searchY + searchH - 1 },
    chips  = { x1 = 1,            y1 = chipsY,  x2 = w,           y2 = chipsY + chipsH - 1 },
    grid   = { x1 = gridX1,       y1 = bodyTop, x2 = gridX2,      y2 = bodyBot },
    scroll = { x1 = gridX2 + pad, y1 = bodyTop, x2 = w,           y2 = bodyBot },
    up     = { x1 = gridX2 + pad, y1 = bodyTop, x2 = w,           y2 = bodyTop + 28 },
    down   = { x1 = gridX2 + pad, y1 = bodyBot - 28, x2 = w,      y2 = bodyBot },
    cart   = { x1 = 1,            y1 = bodyTop, x2 = cartW,       y2 = bodyBot },
    cartUp   = { x1 = cartW - 24, y1 = bodyTop, x2 = cartW,       y2 = bodyTop + 18 },
    cartDown = { x1 = cartW - 24, y1 = bodyBot - 18, x2 = cartW,  y2 = bodyBot },
    cartScroll = { x1 = 1,        y1 = bodyTop + 20, x2 = cartW,  y2 = bodyBot - 20 },
    status = { x1 = 1,            y1 = statusY, x2 = w,           y2 = btnY - 1 },
    btns   = { x1 = 1,            y1 = btnY,    x2 = w,           y2 = h },
    cartW = cartW, pad = pad,
  }
end

-- Цикл шага накопления для GPU-тача: 1 → 16 → 32 → 64 → 1.
function M.nextStep4(step)
  if step == 1 then return 16
  elseif step == 16 then return 32
  elseif step == 32 then return 64
  else return 1 end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: PASS — all `layoutPx`/`nextStep4` checks `ok`, 0 FAIL.

- [ ] **Step 5: Commit**

```bash
git add src/ui_logic.lua test/spec.lua
git commit -m "$(cat <<'EOF'
feat: ui_logic.layoutPx + nextStep4 for GPU pixel grid

Pixel zone map (left cart w/ own scroll, right grid, bottom buttons)
plus the 1/16/32/64 step cycle used by the GPU backend.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

### Task 2.2: `test/mock-gpu.lua` (Tom's GPU stub)

**Files:**
- Create: `test/mock-gpu.lua`

**Interfaces:**
- Produces: `require("mock-gpu").new(wpx, hpx) -> gpu` where `gpu` has `getSize`, `filledRectangle`, `rectangle`, `line`, `lineS`, `drawText`, `drawImage`, `decodeImage`, `newImage`, `imageFromBuffer`, `setSize`, `fill`, `sync`, and `gpu._calls` (ordered list of `{op=..., ...}`), `gpu._images` (decoded refs).

- [ ] **Step 1: Create the mock**

Create `test/mock-gpu.lua`:

```lua
-- Стаб Tom's Peripherals GPU для headless-тестов. Пишет каждый вызов в _calls,
-- decodeImage возвращает фейковый image-ref с .free(). Ничего не рисует.
local M = {}

function M.new(w, h)
  w = w or 328; h = h or 200
  local calls = {}
  local nextId = 0
  local function rec(op, t) t = t or {}; t.op = op; calls[#calls + 1] = t; return t end
  local gpu = { _calls = calls }
  function gpu.getSize() return w, h end
  function gpu.setSize(res) rec("setSize", { res = res }) end
  function gpu.fill(c) rec("fill", { c = c }) end
  function gpu.filledRectangle(x, y, ww, hh, c) rec("filledRectangle", { x = x, y = y, w = ww, h = hh, c = c }) end
  function gpu.rectangle(x, y, ww, hh, c) rec("rectangle", { x = x, y = y, w = ww, h = hh, c = c }) end
  function gpu.line(x1, y1, x2, y2, c) rec("line", { x1 = x1, y1 = y1, x2 = x2, y2 = y2, c = c }) end
  function gpu.lineS(x1, y1, x2, y2, c, s) rec("lineS", { x1 = x1, y1 = y1, x2 = x2, y2 = y2, c = c, s = s }) end
  function gpu.drawText(x, y, s, fg, bg, size, pad) rec("drawText", { x = x, y = y, s = s, fg = fg, bg = bg, size = size }) end
  function gpu.drawImage(x, y, ref) rec("drawImage", { x = x, y = y, ref = ref }) end
  function gpu.decodeImage(bytes)
    nextId = nextId + 1
    local id = nextId
    rec("decodeImage", { id = id, len = bytes and #bytes or 0 })
    return { _id = id, free = function() rec("free", { id = id }) end }
  end
  function gpu.newImage(ww, hh) nextId = nextId + 1; return { _id = nextId, w = ww, h = hh } end
  function gpu.imageFromBuffer() nextId = nextId + 1; return { _id = nextId } end
  function gpu.sync() rec("sync") end
  return gpu
end

return M
```

- [ ] **Step 2: Verify it loads**

Run: `cd /home/davidadmin/claudeproject/projects/cc-storage-terminal && ~/.local/bin/lua5.1 -e 'package.path="./test/?.lua;"..package.path; local g=require("mock-gpu").new(); g.filledRectangle(1,1,4,4,0xFFFFFFFF); g.sync(); assert(#g._calls==2); print("mock-gpu OK")'`
Expected: `mock-gpu OK`.

- [ ] **Step 3: Commit**

```bash
git add test/mock-gpu.lua
git commit -m "$(cat <<'EOF'
test: add Tom's GPU mock for headless render_gpu tests

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

### Task 2.3: `render_gpu.lua` — palette, perPage, backend stubs

**Files:**
- Create: `src/render_gpu.lua`
- Test: `test/spec.lua`

**Interfaces:**
- Produces: `render_gpu.applyPalette(surface)` (no-op — GPU is full-color), `render_gpu.defaultStep = 32`, `render_gpu.nextStep(step) = ui_logic.nextStep4`, `render_gpu.perPage(surface) -> number`, `render_gpu.draw(surface, model) -> hit` (filled in Task 2.4).
- Consumes: `ui_logic.{layoutPx, gridDims, nextStep4}`.

- [ ] **Step 1: Write the failing test**

Add to `test/spec.lua`:

```lua
-- render_gpu backend basics
do
  package.path = "./test/?.lua;" .. package.path
  local mockgpu = require("mock-gpu")
  local rg = require("render_gpu")
  local ui = require("ui_logic")
  check("render_gpu.defaultStep = 32", rg.defaultStep == 32)
  check("render_gpu.nextStep = nextStep4",
    rg.nextStep(1) == 16 and rg.nextStep(64) == 1)
  local g = mockgpu.new(328, 200)
  local P = ui.layoutPx(328, 200)
  local expect = ui.gridDims(P.grid, 56, 44, 4).perPage
  check("render_gpu.perPage = gridDims(layoutPx) по getSize",
    rg.perPage(g) == expect)
  check("render_gpu.applyPalette не падает (full-color no-op)",
    (function() rg.applyPalette(g); return true end)())
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: FAIL — `module 'render_gpu' not found`.

- [ ] **Step 3: Create `src/render_gpu.lua` skeleton (palette/perPage/step)**

```lua
-- GPU-рендер (Tom's Peripherals). Пиксельные плитки, крупный текст, реальные
-- иконки (Phase 3). Полноцвет ARGB — палитру не перекраиваем. Chrome — English
-- ASCII. Возвращает хит-зоны в пикселях. Тач: тап=+step, sneak+тап=+16.
local ui_logic = require("ui_logic")
local M = {}

-- Стимпанк-палитра как ARGB 0xAARRGGBB.
local C = {
  bg       = 0xFF2A2925, -- тёмный андезит
  panel    = 0xFF3A3833, -- панель
  casing   = 0xFF8F8F86, -- андезит-корпус
  casingHi = 0xFFC2C2B6, -- светлый андезит (bevel)
  casingLo = 0xFF5A5A52, -- тёмный ридж
  text     = 0xFFE8DEC8, -- парчмент
  ink      = 0xFF1E1C18, -- near-black на светлом
  muted    = 0xFF9A9486, -- приглушённый
  brass    = 0xFFC8A24A, -- латунь — акцент
  brassHi  = 0xFFE3C77A, -- светлая латунь
  copper   = 0xFFB5512A, -- медь — danger/X
}

-- Цвет иконки-категории (пиксель-глиф, пока нет реальной текстуры).
local CAT = {
  Create = 0xFFC8A24A, Redstone = 0xFFB5512A, Resources = 0xFF6E90B0,
  Wood = 0xFF7A5A38, Stone = 0xFF7E8A86, Building = 0xFFB5663B,
  Other = 0xFF6B6458, All = 0xFF8F8F86,
}
M._C = C
M._CAT = CAT

-- размеры плитки в пикселях (подбираются in-game, см. TODO в spec)
local TILE_W, TILE_H, GAP = 56, 44, 4

M.defaultStep = 32

function M.nextStep(step)
  return ui_logic.nextStep4(step)
end

-- GPU полноцветный — перекрашивать палитру не нужно.
function M.applyPalette(_surface) end

function M.perPage(surface)
  local w, h = surface.getSize()
  local P = ui_logic.layoutPx(w, h)
  return ui_logic.gridDims(P.grid, TILE_W, TILE_H, GAP).perPage
end

-- M.draw реализуется в Task 2.4.
function M.draw(surface, model)
  return { tiles = {}, chips = {} }
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: PASS — `render_gpu.*` checks `ok`, 0 FAIL.

- [ ] **Step 5: Commit**

```bash
git add src/render_gpu.lua test/spec.lua
git commit -m "$(cat <<'EOF'
feat: render_gpu skeleton (palette, perPage, step cycle)

ARGB steampunk palette, 32 default step, 1/16/32/64 cycle, pixel
per-page math via layoutPx. draw() filled in next task.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

### Task 2.4: `render_gpu.draw` — tiles, cart, buttons, category icons, hit zones

**Files:**
- Modify: `src/render_gpu.lua` (replace `M.draw` stub + add draw helpers)
- Test: `test/spec.lua`

**Interfaces:**
- Produces: `render_gpu.draw(surface, model) -> hit` where `hit = { tiles={{rect,entry}...}, chips={{rect,group}...}, search, addr, up?, down?, step, clear?, confirm?, cartUp?, cartDown? }` — same hit-zone contract `server.lua` already routes.
- Consumes: `ui_logic.{layoutPx, gridDims, tiles, chips, basketQty, basketList, basketTotals, page, wrap2}`.

- [ ] **Step 1: Write the failing test**

Add to `test/spec.lua`:

```lua
-- render_gpu.draw produces tiles + hit zones + calls the GPU
do
  local mockgpu = require("mock-gpu")
  local rg = require("render_gpu")
  local ui = require("ui_logic")
  local g = mockgpu.new(328, 200)
  local model = {
    items = {
      { id = "create:cogwheel", display = "Cogwheel", count = 128, group = "Create" },
      { id = "minecraft:iron_ingot", display = "Iron Ingot", count = 512, group = "Resources" },
    },
    groups = { "All", "Create", "Resources" }, group = "All",
    query = "", searchFocus = false, scroll = 0,
    address = "Main", basket = ui.basketNew(), step = 32, toast = nil,
  }
  ui.basketAdd(model.basket, model.items[1], 32)
  local hit = rg.draw(g, model)
  check("gpu.draw: вернул плитки (2 items)", #hit.tiles == 2)
  check("gpu.draw: плитка несёт entry", hit.tiles[1].entry.id == "create:cogwheel")
  check("gpu.draw: есть search/addr хит-зоны", hit.search ~= nil and hit.addr ~= nil)
  check("gpu.draw: есть step-кнопка", hit.step ~= nil)
  check("gpu.draw: confirm появился (корзина непуста)", hit.confirm ~= nil)
  check("gpu.draw: рисовал на GPU (filledRectangle вызван)",
    (function() for _, c in ipairs(g._calls) do if c.op == "filledRectangle" then return true end end return false end)())
  check("gpu.draw: писал текст имени предмета",
    (function() for _, c in ipairs(g._calls) do if c.op == "drawText" and c.s and c.s:find("Cogwheel", 1, true) then return true end end return false end)())
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: FAIL — `gpu.draw: вернул плитки (2 items)` fails (stub returns empty tiles), and the drawText/confirm checks fail.

- [ ] **Step 3: Implement `M.draw` and helpers**

In `src/render_gpu.lua`, add these helpers above `M.draw` (after `M.perPage`):

```lua
-- ===== Низкоуровневые помощники рисования =====
local function rect(g, r, color)
  g.filledRectangle(r.x1, r.y1, r.x2 - r.x1 + 1, r.y2 - r.y1 + 1, color)
end

-- beveled-панель: заливка + светлый верх/лево, тёмный низ/право (объём корпуса).
local function bevel(g, r, face, hi, lo)
  rect(g, r, face)
  g.line(r.x1, r.y1, r.x2, r.y1, hi)
  g.line(r.x1, r.y1, r.x1, r.y2, hi)
  g.line(r.x1, r.y2, r.x2, r.y2, lo)
  g.line(r.x2, r.y1, r.x2, r.y2, lo)
end

local function trunc(s, max)
  if max <= 0 then return "" end
  if #s <= max then return s end
  if max <= 2 then return s:sub(1, max) end
  return s:sub(1, max - 2) .. ".."
end

-- Пиксель-глиф категории: 32x32 блок цвета категории с рамкой (заглушка вместо
-- реальной текстуры; Phase 3 заменит на drawImage).
local function catIcon(g, x, y, group)
  local col = CAT[group] or C.muted
  g.filledRectangle(x, y, 32, 32, col)
  g.rectangle(x, y, 32, 32, C.ink)
  g.filledRectangle(x + 12, y + 12, 8, 8, C.ink) -- метка-«ядро»
end

-- одна плитка предмета (иконка + сток + полное имя + бейдж корзины).
local function drawTile(g, t, model)
  local r, e = t.rect, t.entry
  local inCart = ui_logic.basketQty(model.basket, e.id)
  local pressed = model.pressed == e.id
  local face = pressed and C.casingHi or C.panel
  local frame = inCart > 0 and C.brass or C.casingLo
  bevel(g, r, face, frame, frame)
  catIcon(g, r.x1 + 4, r.y1 + 4, e.group)
  -- сток справа сверху
  g.drawText(r.x1 + 40, r.y1 + 6, "x" .. e.count, C.muted, nil, 1)
  -- бейдж корзины
  if inCart > 0 then
    g.drawText(r.x1 + 40, r.y1 + 18, "+" .. inCart, C.brass, nil, 1)
  end
  -- полное имя в 2 строки снизу
  local lines = ui_logic.wrap2(e.display, 11)
  g.drawText(r.x1 + 4, r.y2 - 18, lines[1], C.text, nil, 1)
  if lines[2] ~= "" then g.drawText(r.x1 + 4, r.y2 - 8, lines[2], C.text, nil, 1) end
end

-- кнопка справа налево; возвращает rect и сдвигает rx.
local function btnRow(g, state, label, face, fg)
  local pad = 8
  local wbtn = #label * 6 + pad * 2
  local x1 = state.rx - wbtn + 1
  local r = { x1 = x1, y1 = state.y1, x2 = state.rx, y2 = state.y2 }
  bevel(g, r, face, C.casingHi, C.casingLo)
  g.drawText(x1 + pad, state.y1 + 6, label, fg, nil, 1)
  state.rx = x1 - state.pad
  return r
end
```

Then replace the `M.draw` stub with the full implementation:

```lua
function M.draw(surface, model)
  local g = surface
  local w, h = g.getSize()
  local P = ui_logic.layoutPx(w, h)
  g.filledRectangle(1, 1, w, h, C.bg)
  local hit = { tiles = {}, chips = {} }

  -- title: STORAGE + адрес справа (латунь)
  bevel(g, P.title, C.panel, C.casingHi, C.casingLo)
  g.drawText(P.title.x1 + 6, P.title.y1 + 4, "STORAGE", C.brass, nil, 1)
  rect(g, P.addr, C.brass)
  g.drawText(P.addr.x1 + 6, P.addr.y1 + 4, trunc("Deliver: " .. (model.address or "?") .. " >", 22), C.bg, nil, 1)
  hit.addr = P.addr

  -- search
  local focused = model.searchFocus
  rect(g, P.search, focused and C.brass or C.panel)
  local q = (model.query ~= "" and model.query) or "type to filter..."
  g.drawText(P.search.x1 + 6, P.search.y1 + 3, "Search: " .. q, focused and C.bg or C.text, nil, 1)
  g.drawText(P.search.x2 - 80, P.search.y1 + 3, #model.items .. " items", focused and C.bg or C.muted, nil, 1)
  hit.search = P.search

  -- чипы категорий
  rect(g, P.chips, C.bg)
  local chips = ui_logic.chips(model.groups, P.chips.x1 + 2, P.chips.y1, w, 1)
  local cx = P.chips.x1 + 4
  for _, c in ipairs(chips) do
    local active = (c.group == model.group)
    local wlab = #c.label * 6 + 12
    local r = { x1 = cx, y1 = P.chips.y1, x2 = cx + wlab - 1, y2 = P.chips.y2 }
    bevel(g, r, active and C.brass or C.casing, active and C.brassHi or C.casingHi, C.casingLo)
    g.drawText(cx + 6, P.chips.y1 + 4, c.label, active and C.bg or C.ink, nil, 1)
    hit.chips[#hit.chips + 1] = { rect = r, group = c.group }
    cx = cx + wlab + 4
    if cx > w then break end
  end

  -- грид плиток
  local dims = ui_logic.gridDims(P.grid, TILE_W, TILE_H, GAP)
  local step = { x = TILE_W + GAP, y = TILE_H + GAP }
  local pg = ui_logic.page(model.items, model.scroll or 0, dims.perPage)
  model.scroll = pg.scroll
  for i, e in ipairs(pg.slice) do
    local idx = i - 1
    local col = idx % dims.cols
    local row = math.floor(idx / dims.cols)
    local x1 = P.grid.x1 + col * step.x
    local y1 = P.grid.y1 + row * step.y
    local r = { x1 = x1, y1 = y1, x2 = x1 + TILE_W - 1, y2 = y1 + TILE_H - 1 }
    local t = { entry = e, rect = r }
    drawTile(g, t, model)
    hit.tiles[#hit.tiles + 1] = { rect = r, entry = e }
  end

  -- scroll-колонка: стрелки грида
  rect(g, P.scroll, C.bg)
  if pg.hasUp then
    bevel(g, P.up, C.brass, C.brassHi, C.casingLo)
    g.drawText(P.up.x1 + 6, P.up.y1 + 8, "^", C.bg, nil, 2)
    hit.up = P.up
  end
  if pg.hasDown then
    bevel(g, P.down, C.brass, C.brassHi, C.casingLo)
    g.drawText(P.down.x1 + 6, P.down.y1 + 8, "v", C.bg, nil, 2)
    hit.down = P.down
  end

  -- панель корзины (слева) с собственной прокруткой
  local totals = ui_logic.basketTotals(model.basket)
  bevel(g, P.cart, C.panel, C.casingHi, C.casingLo)
  g.drawText(P.cart.x1 + 6, P.cart.y1 + 4, trunc("CART " .. totals.units .. "u", 16), C.brass, nil, 1)
  local list = ui_logic.basketList(model.basket)
  local rowH = 12
  local listTop = P.cart.y1 + 22
  local listRows = math.max(1, math.floor((P.cart.y2 - 20 - listTop) / rowH))
  local cpg = ui_logic.page(list, model.cartScroll or 0, listRows)
  model.cartScroll = cpg.scroll
  if #list == 0 then
    g.drawText(P.cart.x1 + 6, listTop, "empty - tap tiles", C.muted, nil, 1)
  else
    for i, b in ipairs(cpg.slice) do
      local y = listTop + (i - 1) * rowH
      g.drawText(P.cart.x1 + 6, y, trunc(b.qty .. "x " .. b.entry.display, 18), C.text, nil, 1)
    end
    if cpg.hasUp then
      bevel(g, P.cartUp, C.casing, C.casingHi, C.casingLo)
      g.drawText(P.cartUp.x1 + 6, P.cartUp.y1 + 4, "^", C.ink, nil, 1)
      hit.cartUp = P.cartUp
    end
    if cpg.hasDown then
      bevel(g, P.cartDown, C.casing, C.casingHi, C.casingLo)
      g.drawText(P.cartDown.x1 + 6, P.cartDown.y1 + 4, "v", C.ink, nil, 1)
      hit.cartDown = P.cartDown
    end
  end

  -- статус-строка
  rect(g, P.status, C.bg)
  local hint = model.toast or "Tap +" .. (model.step or 32) .. "  |  Sneak+tap +16  |  Step cycles"
  g.drawText(P.status.x1 + 4, P.status.y1 + 3, trunc(hint, 60), model.toast and C.brassHi or C.muted, nil, 1)

  -- ряд кнопок (низ): Step / Clear / Confirm справа налево
  rect(g, P.btns, C.bg)
  local state = { rx = w - 4, y1 = P.btns.y1 + 2, y2 = P.btns.y2 - 2, pad = 6 }
  hit.step = btnRow(g, state, "Step:" .. (model.step or 32), C.casing, C.ink)
  if totals.lines > 0 then
    hit.clear = btnRow(g, state, "Clear", C.copper, C.text)
    hit.confirm = btnRow(g, state, "Confirm", C.brass, C.bg)
  end

  if g.sync then g.sync() end
  return hit
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: PASS — all `gpu.draw:` checks `ok`, 0 FAIL.

- [ ] **Step 5: Wire cart-scroll touch in `server.lua`**

Add cart-scroll handling in `server.lua` `handleTouch`, right after the `hit.down` branch (around line 91):

```lua
  if hit.cartUp and ui_logic.inside(hit.cartUp, x, y) then
    model.cartScroll = (model.cartScroll or 0) - 1
    return
  end
  if hit.cartDown and ui_logic.inside(hit.cartDown, x, y) then
    model.cartScroll = (model.cartScroll or 0) + 1
    return
  end
```

Run: `~/.local/bin/lua5.1 test/smoke.lua && ~/.local/bin/lua5.1 test/spec.lua`
Expected: smoke `smoke OK`; spec 0 FAIL.

- [ ] **Step 6: Commit**

```bash
git add src/render_gpu.lua src/server.lua test/spec.lua
git commit -m "$(cat <<'EOF'
feat: render_gpu.draw with pixel tiles, scrollable cart, category icons

Big tiles (32px glyph + full 2-line name + stock + cart badge), left
cart panel with its own scroll, bottom Step/Clear/Confirm row. Server
routes cart scroll touches. Real textures land in Phase 3.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

### Task 2.5: `test/preview-gpu.lua` eye-check + regen installer

**Files:**
- Create: `test/preview-gpu.lua`
- Regenerate: `installer.lua`

- [ ] **Step 1: Create the preview dumper**

Create `test/preview-gpu.lua`:

```lua
-- Глаз-чек GPU-рендера: гоняет render_gpu.draw на мок-GPU и печатает
-- сводку вызовов (типы + ключевой текст). Размер пикселей: arg1 x arg2.
package.path = "./src/?.lua;./test/?.lua;" .. package.path
require("mock-cc")
local mockgpu = require("mock-gpu")
local rg = require("render_gpu")
local ui = require("ui_logic")

local W = tonumber(arg[1]) or 328
local H = tonumber(arg[2]) or 200
local g = mockgpu.new(W, H)
local model = {
  items = {
    { id = "create:cogwheel", display = "Cogwheel", count = 128, group = "Create" },
    { id = "create:large_cogwheel", display = "Large Cogwheel", count = 64, group = "Create" },
    { id = "minecraft:iron_ingot", display = "Iron Ingot", count = 999, group = "Resources" },
    { id = "minecraft:redstone", display = "Redstone Dust", count = 4096, group = "Redstone" },
    { id = "minecraft:oak_log", display = "Oak Log", count = 320, group = "Wood" },
  },
  groups = { "All", "Create", "Redstone", "Resources", "Wood" }, group = "All",
  query = "", searchFocus = false, scroll = 0,
  address = "Main", basket = ui.basketNew(), step = 32, toast = nil,
}
ui.basketAdd(model.basket, model.items[1], 32)
ui.basketAdd(model.basket, model.items[3], 64)
local hit = rg.draw(g, model)

local counts = {}
for _, c in ipairs(g._calls) do counts[c.op] = (counts[c.op] or 0) + 1 end
print(string.format("=== GPU preview %dx%d ===", W, H))
for op, n in pairs(counts) do print(string.format("  %-16s x%d", op, n)) end
print("--- text drawn ---")
for _, c in ipairs(g._calls) do
  if c.op == "drawText" then print("  " .. tostring(c.s)) end
end
print(string.format("--- hit: %d tiles, %d chips, step=%s confirm=%s cartUp=%s",
  #hit.tiles, #hit.chips, tostring(hit.step ~= nil), tostring(hit.confirm ~= nil), tostring(hit.cartUp ~= nil)))
```

- [ ] **Step 2: Run the preview (wide + narrow)**

Run: `cd /home/davidadmin/claudeproject/projects/cc-storage-terminal && ~/.local/bin/lua5.1 test/preview-gpu.lua 328 200 && ~/.local/bin/lua5.1 test/preview-gpu.lua 220 160`
Expected: prints call-type histogram, the drawn item names (`Cogwheel`, `Iron Ingot`, ...), and a hit summary showing tiles ≥ 1, `step=true`, `confirm=true`. No errors.

- [ ] **Step 3: Regenerate + sanity-load installer**

Run: `~/.local/bin/lua5.1 scripts/gen-installer.lua && ~/.local/bin/lua5.1 -e 'assert(loadfile("installer.lua"))' && echo OK`
Expected: installer regenerated with `render_gpu.lua` bundled; `OK`.

- [ ] **Step 4: Commit**

```bash
git add test/preview-gpu.lua installer.lua
git commit -m "$(cat <<'EOF'
test: GPU render preview dump + regen installer with render_gpu

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — Icon pipeline (real textures)

### Task 3.1: `icons.lua` pure helpers — `idToFile` + `parseLayer0`

**Files:**
- Create: `src/icons.lua`
- Test: `test/spec.lua`

**Interfaces:**
- Produces: `icons.idToFile(id) -> string` (`create:cogwheel` → `create__cogwheel.png`), `icons.parseLayer0(modelTable) -> string|nil` (returns the `layer0` texture path for `item/generated` models, else nil).
- Consumed by: `build-icons.py` mirrors `idToFile` logic; `render_gpu` uses `idToFile` at runtime.

- [ ] **Step 1: Write the failing test**

Add to `test/spec.lua`:

```lua
-- icons: чистые помощники маппинга
local icons = require("icons")
check("idToFile: namespace:name -> ns__name.png",
  icons.idToFile("create:cogwheel") == "create__cogwheel.png")
check("idToFile: без namespace -> minecraft__name.png",
  icons.idToFile("apple") == "minecraft__apple.png")
check("parseLayer0: item/generated отдаёт layer0",
  icons.parseLayer0({ parent = "minecraft:item/generated",
    textures = { layer0 = "create:item/cogwheel" } }) == "create:item/cogwheel")
check("parseLayer0: 3D/блок-модель без layer0 -> nil",
  icons.parseLayer0({ parent = "create:block/cogwheel" }) == nil)
check("parseLayer0: handheld тоже item-модель -> layer0",
  icons.parseLayer0({ parent = "minecraft:item/handheld",
    textures = { layer0 = "minecraft:item/iron_pickaxe" } }) == "minecraft:item/iron_pickaxe")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: FAIL — `module 'icons' not found`.

- [ ] **Step 3: Create `src/icons.lua` (pure half only)**

```lua
-- Иконки предметов для GPU-бэкенда. Чистые помощники (маппинг id→файл,
-- разбор item-модели) + рантайм-загрузка (ленивый wget + decodeImage + LRU).
-- Рантайм-часть использует CC API (fs/http), под тестом не вызывается.
local M = {}

-- id предмета → имя файла иконки. namespace:name → ns__name.png.
-- Без namespace считаем minecraft.
function M.idToFile(id)
  local ns, name = id:match("^(.-):(.+)$")
  if not ns then ns, name = "minecraft", id end
  return ns .. "__" .. name .. ".png"
end

-- Из таблицы item-модели достать layer0 (плоская item-текстура).
-- Возвращает строку-путь текстуры или nil (3D/блок-модель — пропускаем).
function M.parseLayer0(model)
  if not model or type(model) ~= "table" then return nil end
  local parent = model.parent or ""
  -- item/generated и item/handheld — плоские item-модели со слоями
  local isItem = parent:find("item/generated", 1, true) or parent:find("item/handheld", 1, true)
  if not isItem then return nil end
  if model.textures and model.textures.layer0 then return model.textures.layer0 end
  return nil
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: PASS — all `icons` checks `ok`, 0 FAIL.

- [ ] **Step 5: Commit**

```bash
git add src/icons.lua test/spec.lua
git commit -m "$(cat <<'EOF'
feat: icons.lua pure helpers (idToFile, parseLayer0)

id->filename mapping and item-model layer0 extraction, shared by the
offline builder and runtime loader. Runtime fetch/cache lands next.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

### Task 3.2: `icons.lua` runtime — lazy load + LRU cache

**Files:**
- Modify: `src/icons.lua` (add `M.get`, LRU, `M.configure`)
- Test: `test/spec.lua`

**Interfaces:**
- Produces: `icons.configure({ http=, fs=, decode=, baseUrl=, dir=, limit= })` (DI for tests), `icons.get(id) -> imageRef|nil` (cached; lazy-fetches PNG, decodes, evicts LRU calling `ref.free()`), `icons.cacheCount() -> number`.
- Consumes: `M.idToFile`.

- [ ] **Step 1: Write the failing test**

Add to `test/spec.lua`:

```lua
-- icons runtime: ленивый кэш + LRU + free при вытеснении
do
  local icons = require("icons")
  local freed = {}
  local fetched = {}
  -- мок http/fs/decode через DI
  icons.configure({
    baseUrl = "http://x/", dir = "/icons", limit = 2,
    exists = function(_) return false end,
    fetch = function(url) fetched[#fetched + 1] = url; return "PNGBYTES:" .. url end,
    decode = function(bytes) return { bytes = bytes, free = function(self) freed[#freed + 1] = self.bytes end } end,
  })
  local a = icons.get("create:cogwheel")
  check("icons.get: декодировал и вернул ref", a ~= nil and a.bytes:find("create__cogwheel.png", 1, true) ~= nil)
  local a2 = icons.get("create:cogwheel")
  check("icons.get: второй вызов из кэша (один fetch)", a2 == a and #fetched == 1)
  icons.get("minecraft:iron_ingot")  -- кэш = 2
  icons.get("minecraft:redstone")    -- лимит 2 → вытеснение самого старого (cogwheel)
  check("icons.get: LRU вытеснил и вызвал free", #freed == 1 and freed[1]:find("cogwheel", 1, true) ~= nil)
  check("icons.cacheCount: держит лимит", icons.cacheCount() == 2)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: FAIL — `attempt to call field 'configure' (a nil value)`.

- [ ] **Step 3: Add the runtime cache to `src/icons.lua`**

Insert before the final `return M`:

```lua
-- ===== Рантайм: ленивая загрузка + LRU =====
-- Конфигурируется через DI (тест подменяет fetch/decode/fs).
local cfg = {
  baseUrl = "https://raw.githubusercontent.com/davidsuarko-droid/cc-storage-terminal/main/icons/",
  dir = "/icons",
  limit = 64,
  exists = function(p) return fs and fs.exists(p) end,
  -- читает PNG: сперва с диска, иначе wget по сети, кладёт на диск
  fetch = function(url) return nil end,
  decode = function(bytes) return nil end,
}

-- кэш: map[id]=ref, order = очередь использования (последний — свежий)
local cache = {}
local order = {}

function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  cache = {}; order = {}
end

function M.cacheCount()
  local n = 0
  for _ in pairs(cache) do n = n + 1 end
  return n
end

local function touch(id)
  for i, v in ipairs(order) do
    if v == id then table.remove(order, i); break end
  end
  order[#order + 1] = id
end

local function evictIfNeeded()
  while #order > cfg.limit do
    local victim = table.remove(order, 1)
    local ref = cache[victim]
    cache[victim] = nil
    if ref and ref.free then ref:free() end
  end
end

-- Вернуть image-ref иконки для id или nil (нет файла/сети/декода).
function M.get(id)
  if cache[id] then touch(id); return cache[id] end
  local file = M.idToFile(id)
  local bytes = cfg.fetch(cfg.baseUrl .. file)
  if not bytes then return nil end
  local ok, ref = pcall(cfg.decode, bytes)
  if not ok or not ref then return nil end
  cache[id] = ref
  touch(id)
  evictIfNeeded()
  return ref
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: PASS — all `icons runtime` checks `ok`, 0 FAIL.

- [ ] **Step 5: Commit**

```bash
git add src/icons.lua test/spec.lua
git commit -m "$(cat <<'EOF'
feat: icons runtime lazy-load + LRU cache with free() eviction

DI-configured fetch/decode so the cache is unit-tested headless; evicts
oldest ref and frees its GPU image when over the limit.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

### Task 3.3: Wire real `fetch`/`decode` + `render_gpu` uses icons

**Files:**
- Modify: `src/icons.lua` (add `M.initRuntime` with real CC fs/http/decode wiring)
- Modify: `src/render_gpu.lua` (`catIcon` → try real icon, fall back to glyph; init icons on first draw)
- Test: `test/spec.lua` (icon used path via mock-gpu + configured fetch/decode)

**Interfaces:**
- Consumes: `icons.{configure, get, initRuntime}`.
- Produces: `icons.initRuntime(gpu)` (sets `fetch` = disk-or-wget, `decode` = `gpu.decodeImage`); `render_gpu.draw` draws `gpu.drawImage` when `icons.get` returns a ref, else the category glyph.

- [ ] **Step 1: Write the failing test**

Add to `test/spec.lua`:

```lua
-- render_gpu: использует реальную иконку, когда icons.get отдаёт ref
do
  local mockgpu = require("mock-gpu")
  local icons = require("icons")
  local rg = require("render_gpu")
  local ui = require("ui_logic")
  local g = mockgpu.new(328, 200)
  -- icons настроен отдавать ref для всех id (фейк-байты)
  icons.configure({
    baseUrl = "http://x/", dir = "/icons", limit = 8,
    fetch = function(url) return "BYTES" end,
    decode = function(bytes) return g.decodeImage(bytes) end,
  })
  rg.useIcons(icons)  -- инъекция icons-модуля в рендер
  local model = {
    items = { { id = "create:cogwheel", display = "Cogwheel", count = 128, group = "Create" } },
    groups = { "All" }, group = "All", query = "", searchFocus = false, scroll = 0,
    address = "Main", basket = ui.basketNew(), step = 32,
  }
  rg.draw(g, model)
  check("gpu.draw: вызвал drawImage для реальной иконки",
    (function() for _, c in ipairs(g._calls) do if c.op == "drawImage" then return true end end return false end)())
end
-- и фолбэк: без icons рисует глиф (filledRectangle), не падает
do
  local mockgpu = require("mock-gpu")
  local rg = require("render_gpu")
  local ui = require("ui_logic")
  rg.useIcons(nil)
  local g = mockgpu.new(328, 200)
  local model = {
    items = { { id = "create:weird_block", display = "Weird", count = 1, group = "Create" } },
    groups = { "All" }, group = "All", query = "", searchFocus = false, scroll = 0,
    address = "Main", basket = ui.basketNew(), step = 32,
  }
  check("gpu.draw без icons не падает", (function() rg.draw(g, model); return true end)())
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.local/bin/lua5.1 test/spec.lua`
Expected: FAIL — `attempt to call field 'useIcons' (a nil value)`.

- [ ] **Step 3: Add `useIcons` + icon draw to `render_gpu.lua`**

Add near the top of `src/render_gpu.lua` (after `local M = {}`):

```lua
local _icons = nil  -- модуль icons (инъекция через M.useIcons); nil = только глифы
function M.useIcons(mod) _icons = mod end
```

Change `catIcon` to try a real icon first. Replace the `catIcon` function with:

```lua
-- иконка предмета: реальная текстура (drawImage) если есть, иначе глиф категории.
local function drawIcon(g, x, y, e)
  if _icons then
    local ref = _icons.get(e.id)
    if ref then g.drawImage(x, y, ref); return end
  end
  local col = CAT[e.group] or C.muted
  g.filledRectangle(x, y, 32, 32, col)
  g.rectangle(x, y, 32, 32, C.ink)
  g.filledRectangle(x + 12, y + 12, 8, 8, C.ink)
end
```

In `drawTile`, replace the `catIcon(g, r.x1 + 4, r.y1 + 4, e.group)` call with:

```lua
  drawIcon(g, r.x1 + 4, r.y1 + 4, e)
```

- [ ] **Step 4: Add `initRuntime` to `icons.lua`**

Insert before the final `return M` in `src/icons.lua`:

```lua
-- Боевая настройка под CC: чтение с диска или wget, decode через GPU.
function M.initRuntime(gpu)
  M.configure({
    exists = function(p) return fs.exists(p) end,
    fetch = function(url)
      local file = url:match("[^/]+$")
      local path = cfg.dir .. "/" .. file
      if fs.exists(path) then
        local h = fs.open(path, "rb"); local b = h.readAll(); h.close(); return b
      end
      local resp = http and http.get(url, nil, true) -- binary
      if not resp then return nil end
      local b = resp.readAll(); resp.close()
      if b then
        if not fs.exists(cfg.dir) then fs.makeDir(cfg.dir) end
        local h = fs.open(path, "wb"); h.write(b); h.close()
      end
      return b
    end,
    decode = function(bytes) return gpu.decodeImage(bytes) end,
  })
end
```

- [ ] **Step 5: Init icons in `server.lua` when GPU backend chosen**

In `src/server.lua`, in the `if gpu then` branch, after `backend = require("render_gpu")`, wire icons:

```lua
if gpu then
  backend = require("render_gpu")
  surface = gpu
  local icons = require("icons")
  icons.initRuntime(gpu)
  backend.useIcons(icons)
else
```

- [ ] **Step 6: Run tests + smoke to verify pass**

Run: `~/.local/bin/lua5.1 test/spec.lua && ~/.local/bin/lua5.1 test/smoke.lua`
Expected: spec 0 FAIL (drawImage + fallback checks `ok`); smoke `smoke OK`.

- [ ] **Step 7: Commit**

```bash
git add src/render_gpu.lua src/icons.lua src/server.lua test/spec.lua
git commit -m "$(cat <<'EOF'
feat: render_gpu draws real item icons via decodeImage, glyph fallback

Server inits icons runtime (disk-or-wget + GPU decodeImage) and injects
it into render_gpu; tiles drawImage real textures when available, else
the category glyph. No icon dependency under test.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

### Task 3.4: `scripts/build-icons.py` — offline texture extraction

**Files:**
- Create: `scripts/build-icons.py`
- Create (output): `icons/` directory + `icons/manifest.txt` (generated, committed)

**Interfaces:**
- Produces: `icons/<ns>__<name>.png` (flat item textures) + `icons/manifest.txt` (one available id per line). Mirrors `icons.idToFile` mapping and `icons.parseLayer0` logic.

- [ ] **Step 1: Write the extractor**

Create `scripts/build-icons.py`:

```python
#!/usr/bin/env python3
"""Extract flat item-icon PNGs from Minecraft mod jars for cc-storage-terminal.

Reads assets/<ns>/models/item/<name>.json; for item/generated|handheld models
(those with textures.layer0) pulls assets/<ns>/textures/<layer0>.png into
icons/<ns>__<name>.png. 3D/block models (no layer0) are skipped. Writes
icons/manifest.txt listing available item ids.

Usage:
  python3 scripts/build-icons.py <jars_dir> [--out icons]
The jars_dir is the modpack 'mods/' folder (pull via SFTP into a local cache
first; creds in memory reference-minecraft-server-sftp).
"""
import argparse
import json
import os
import sys
import zipfile

ITEM_PARENTS = ("item/generated", "item/handheld")


def texture_to_path(tex):
    # "create:item/cogwheel" -> ("create", "item/cogwheel")
    if ":" in tex:
        ns, rest = tex.split(":", 1)
    else:
        ns, rest = "minecraft", tex
    return ns, rest


def layer0_of(model):
    parent = model.get("parent", "") or ""
    if not any(p in parent for p in ITEM_PARENTS):
        return None
    return (model.get("textures") or {}).get("layer0")


def process_jar(path, out_dir, manifest):
    try:
        zf = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        print(f"skip (bad zip): {path}")
        return 0
    written = 0
    names = zf.namelist()
    nameset = set(names)
    for entry in names:
        # assets/<ns>/models/item/<name>.json
        parts = entry.split("/")
        if len(parts) < 5 or parts[0] != "assets" or parts[2] != "models" or parts[3] != "item":
            continue
        if not entry.endswith(".json"):
            continue
        ns = parts[1]
        item = "/".join(parts[4:])[:-5]  # strip .json, keep nested name
        try:
            model = json.loads(zf.read(entry))
        except (json.JSONDecodeError, KeyError):
            continue
        layer0 = layer0_of(model)
        if not layer0:
            continue
        tns, trest = texture_to_path(layer0)
        tex_entry = f"assets/{tns}/textures/{trest}.png"
        if tex_entry not in nameset:
            continue
        out_name = f"{ns}__{item.replace('/', '_')}.png"
        with open(os.path.join(out_dir, out_name), "wb") as fh:
            fh.write(zf.read(tex_entry))
        manifest.add(f"{ns}:{item}")
        written += 1
    zf.close()
    return written


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jars_dir")
    ap.add_argument("--out", default="icons")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    manifest = set()
    total = 0
    jars = [f for f in os.listdir(args.jars_dir) if f.endswith(".jar")]
    if not jars:
        print(f"no jars in {args.jars_dir}", file=sys.stderr)
        sys.exit(1)
    for j in sorted(jars):
        n = process_jar(os.path.join(args.jars_dir, j), args.out, manifest)
        if n:
            print(f"{j}: {n} icons")
        total += n
    with open(os.path.join(args.out, "manifest.txt"), "w") as fh:
        for item_id in sorted(manifest):
            fh.write(item_id + "\n")
    print(f"done: {total} icons, {len(manifest)} ids -> {args.out}/manifest.txt")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Self-test the extractor logic on a synthetic jar**

Run:

```bash
cd /home/davidadmin/claudeproject/projects/cc-storage-terminal
python3 - <<'PY'
import json, os, zipfile, tempfile, subprocess
d = tempfile.mkdtemp()
jp = os.path.join(d, "test_mod.jar")
with zipfile.ZipFile(jp, "w") as z:
    # flat item: should extract
    z.writestr("assets/create/models/item/cogwheel.json",
               json.dumps({"parent": "item/generated", "textures": {"layer0": "create:item/cogwheel"}}))
    z.writestr("assets/create/textures/item/cogwheel.png", b"\x89PNG\r\n\x1a\nFAKE")
    # 3D block model: should skip
    z.writestr("assets/create/models/item/large_cogwheel.json",
               json.dumps({"parent": "create:block/large_cogwheel"}))
out = os.path.join(d, "icons")
subprocess.check_call(["python3", "scripts/build-icons.py", d, "--out", out])
files = sorted(os.listdir(out))
assert "create__cogwheel.png" in files, files
assert "create__large_cogwheel.png" not in files, files
man = open(os.path.join(out, "manifest.txt")).read().splitlines()
assert man == ["create:cogwheel"], man
print("build-icons self-test OK")
PY
```

Expected: prints `test_mod.jar: 1 icons`, `done: 1 icons, 1 ids ...`, then `build-icons self-test OK`.

- [ ] **Step 3: Add `icons/` placeholder + .gitignore note**

Create `icons/manifest.txt` empty placeholder so the directory exists in-repo (real run populates it):

```bash
mkdir -p icons && : > icons/manifest.txt
```

- [ ] **Step 4: Commit the script (icons populated later from server jars)**

```bash
git add scripts/build-icons.py icons/manifest.txt
git commit -m "$(cat <<'EOF'
feat: build-icons.py offline item-texture extractor

Pulls flat layer0 item textures from mod jars into icons/<ns>__<name>.png
+ manifest.txt; skips 3D/block models. Run against the modpack mods/
folder (SFTP-pulled) to populate icons before deploy.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: (Manual, document only) Populate real icons**

Document in `handoff.md` / spec the populate command (run when ready, needs SFTP pull of `mods/`):

```bash
# pull jars locally (creds: memory reference-minecraft-server-sftp), then:
python3 scripts/build-icons.py /path/to/local/mods --out icons
git add icons/ && git commit -m "chore: populate item icons from Skybound SMP jars"
```

This is a deploy-time data step, not code — leave icons mostly empty in-repo until run. Runtime falls back to glyphs for any missing id, so the build stays green without it.

---

## Phase 4 — Polish + regen + deploy verification

### Task 4.1: Regenerate installer, run full suite, update handoff

**Files:**
- Regenerate: `installer.lua`
- Modify: `handoff.md` (state: GPU backend shipped, icon populate pending), `docs/superpowers/specs/2026-06-19-gpu-render-pivot-design.md` (tick done items — optional)

- [ ] **Step 1: Full test + smoke + preview**

Run:

```bash
cd /home/davidadmin/claudeproject/projects/cc-storage-terminal
~/.local/bin/lua5.1 test/spec.lua && ~/.local/bin/lua5.1 test/smoke.lua \
  && ~/.local/bin/lua5.1 test/preview-gpu.lua 328 200
```

Expected: spec 0 FAIL, `smoke OK`, GPU preview prints tiles + names + hit summary.

- [ ] **Step 2: Regenerate + sanity-load installer**

Run: `~/.local/bin/lua5.1 scripts/gen-installer.lua && ~/.local/bin/lua5.1 -e 'assert(loadfile("installer.lua"))' && echo OK`
Expected: bundles `render_text`, `render_gpu`, `icons`; prints `OK`.

- [ ] **Step 3: Update `handoff.md`**

Append a section to `handoff.md` recording: GPU backend live (auto-selected by `tm_gpu`), pocket + GPU-less server unchanged, real icons require running `build-icons.py` against the modpack jars and committing `icons/`, and the in-game tuning TODOs (pixel tile sizes, font scale, `setSize` resolution) carried from the spec's "Known limitations / TODO".

- [ ] **Step 4: Commit**

```bash
git add installer.lua handoff.md
git commit -m "$(cat <<'EOF'
chore: regen installer with GPU backend + handoff update

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Push**

```bash
git push -q origin HEAD
```

Expected: pushes to `main` (this project's default branch).

### Task 4.2: In-game verification checklist (manual, after deploy)

Not an automated task — record the steps the user runs in Minecraft after `wget run <installer url>` + reboot on the server computer:

- [ ] Craft/place GPU chain (from spec "Что скрафтить/поставить"): GPU Chip (Raw) → smelt → GPU block; Tom's Monitors in a 3×3 grid wired to an Advanced Computer; Stock Ticker + warehouse + Wireless/Ender Modem as before.
- [ ] Reboot server computer → confirm it renders on the Tom's monitor (GPU path), not the old CC monitor.
- [ ] Tiles show 32px icon + full 2-line name + stock `xN`; tap a tile = +32, sneak+tap = +16, Step button cycles 1/16/32/64.
- [ ] Cart panel (left) fills and scrolls with its own ^/v when many items added — overflow fixed.
- [ ] Real icons appear for flat-texture items (after `icons/` populated + pushed); category glyph for 3D blocks/missing.
- [ ] Confirm sends the whole cart to the selected address; Clear empties it.
- [ ] Pocket computer still renders text UI unchanged; a GPU-less server still uses the CC monitor unchanged.

---

## Self-Review

**Spec coverage:**
- Backend split (text/gpu) + `tm_gpu` detect + fallback → Tasks 1.1–1.3 ✓
- `layoutPx` parallel pixel layout → Task 2.1 ✓
- GPU tiles (icon + full name + stock + cart badge), big text → Task 2.4 ✓
- Cart overflow fix (scrollable cart panel) → Tasks 2.1 (`cartScroll`/`cartUp`/`cartDown`), 2.4 (render + server routing) ✓
- Increments: tap +32 / sneak+tap +16 / Step 1/16/32/64 → Task 1.2 (sneak routing, defaultStep), 2.1 (`nextStep4`), 2.3 (`defaultStep`/`nextStep`) ✓
- Icon pipeline: `idToFile` + `parseLayer0` + lazy load + LRU + `decodeImage` + `build-icons.py` → Tasks 3.1–3.4 ✓
- Detect/deploy via same installer → Tasks 1.3, 2.5, 4.1 ✓
- Crafting list / in-game verify → Task 4.2 ✓
- Testing: `layoutPx` units, icon-mapping units, `mock-gpu`, smoke with/without `tm_gpu` → Tasks 2.1, 2.2, 3.1, 3.2, smoke throughout ✓

**Placeholder scan:** All code steps contain full code. Icon population (Task 3.4 Step 5) is intentionally a documented manual data step (needs live SFTP jars), not a code placeholder — runtime falls back to glyphs so the build is green without it.

**Type consistency:** Backend interface uniform across `render_text`/`render_gpu`: `applyPalette(surface)`, `draw(surface, model)->hit`, `perPage(surface)`, `defaultStep`, `nextStep(step)`. `hit` shape consistent (`tiles`/`chips`/`search`/`addr`/`up`/`down`/`step`/`clear`/`confirm`/`cartUp`/`cartDown`). `icons.{idToFile,parseLayer0,configure,get,cacheCount,initRuntime,useIcons-consumer}` consistent between 3.1/3.2/3.3 and `build-icons.py` mirrors the same mapping. `nextStep4` named identically in 2.1 and consumed in 2.3.

## Known limitations / TODO (carried from spec)

- `parseLayer0` handles only `item/generated|handheld` one level deep — multi-level parent chains and 3D block models fall back to the category glyph. Future: recursive parent resolution / headless 3D-model render.
- Lazy `wget` has no offline bundle — if GitHub raw is unreachable, icons stay as glyphs. Future: option to ship the whole pack in the installer.
- Pixel tile sizes (`TILE_W/H/GAP = 56/44/4`), font `size` args, and `setSize` resolution are first guesses — tune in-game against the real Tom's monitor pixel dimensions.
- `decodeImage` confirmed as PNG by source — verify on a real GPU.
- LRU `limit = 64` and VRAM use are guesses — tune against the real device.
```
