# busted-copas — Implementation Specification

## Overview

`busted-copas` is a thin Lua library that enables testing of asynchronous
[Copas](https://github.com/lunarmodules/copas)-based applications with the
[Busted](https://github.com/lunarmodules/busted) test framework.

**The core idea:** instead of busted owning the outermost execution loop and
calling into a scheduler, Copas owns the loop and busted's runner executes as
a Copas coroutine thread. Any test that calls a Copas-native API (socket I/O,
`copas.pause`, timers, etc.) simply yields and resumes naturally — no special
test syntax, no `done()` callbacks, no adapter layer.

The library ships two things:

1. **`bin/busted-copas`** — a script installed to PATH by luarocks, used as
   the `lua` interpreter value in an adopting project's `.busted` config file.
   Busted invokes it as the Lua interpreter for its own main script; it shifts
   the `arg` table, wraps `dofile(busted_script)` in `copas.addthread`, and
   calls `copas.loop()`. The adopting project's users still type plain `busted`
   — no CLI change required.
2. **`src/copas/busted.lua`** — a helper module with assertion-friendly
   utilities for async tests (waiting for conditions, per-test timeouts,
   etc.).

---

## Repository Bootstrap

The repository is created by the **human owner** using the instructions in
`Tieske/project.lua` (the template's own README documents the setup and
initialisation steps). The agent takes over once that process is complete and
a working project scaffold exists.

When the agent starts, it can assume the repository is already initialised.
Key substitutions that will have been made throughout all files during setup:

| Placeholder | Value |
|---|---|
| `<projectname>` | `busted-copas` |
| `<modulename>` | `copas.busted` |
| `<description>` | `Busted test runner and helpers for asynchronous Copas-based applications` |
| `<author>` | Tieske |
| `<license>` | MIT |
| `<luarocks username>` | Tieske |
| `<github username>` | Tieske |

The template provides: LuaRocks rockspec, LDoc config, Luacheck config,
GitHub Actions CI, `Makefile`, and a `spec/` skeleton.

---

## Final Directory Layout

```
busted-copas/
├── .github/
│   └── workflows/
│       └── ci.yml            (from template, verify it installs copas & busted)
├── bin/
│   └── busted-copas          (the Lua-interpreter wrapper, installed to PATH)
├── spec/
│   ├── 01-runner_spec.lua    (tests for the runner behaviour)
│   ├── 02-helpers_spec.lua   (tests for the helper utilities)
│   └── fixtures/
│       ├── passing_spec.lua
│       └── failing_spec.lua
├── src/
│   └── copas/
│       └── busted.lua        (the helper module)
├── .busted                   (busted config for this project's own tests)
├── .luacheckrc
├── config.ld                 (LDoc)
├── busted-copas-scm-1.rockspec
├── Makefile
└── README.md
```

---

## 1. The Interpreter Wrapper — `bin/busted-copas`

`busted-copas` is installed to PATH by luarocks. Adopting projects reference
it as the `lua` interpreter in their `.busted` config (see section 4). When
the user runs `busted`, busted internally invokes `busted-copas` in place of
`lua` to run its own main script — the user's CLI workflow is completely
unchanged.

The invocation busted makes looks like:

```
busted-copas /path/to/busted/main.lua [test-file-args...]
```

Inside `busted-copas`, the argument table is therefore:

```
arg[-1]  the path to busted-copas itself
arg[0]   busted-copas (script name)
arg[1]   /path/to/busted/main.lua   ← the busted entry script
arg[2..] the test-file args busted was given
```

The script shifts `arg` so that busted's main script sees itself as `arg[0]`,
then runs it inside a Copas thread:

```lua
#!/usr/bin/env lua
-------------------------------------------------------------------------------
-- bin/busted-copas
--
-- A Lua interpreter wrapper that runs busted inside a Copas coroutine loop.
-- Referenced via the `lua` key in an adopting project's .busted file:
--
--   return { default = { lua = "busted-copas", ... } }
--
-- Busted invokes this script as:
--   busted-copas <busted-main-script> [args...]
--
-- arg[1] is busted's main script; we shift it to arg[0] so busted's
-- own arg-parsing sees the expected layout, then dofile() it inside
-- copas.addthread() and start copas.loop().
-------------------------------------------------------------------------------
local copas = require "copas"

local busted_script = table.remove(arg, 1)  -- was arg[1]
arg[0] = busted_script                       -- busted expects arg[0] = itself

copas.addthread(function()
  dofile(busted_script)
end)

copas.loop()
```

### Notes

- The script must be marked executable (`chmod +x bin/busted-copas`) and
  listed in the rockspec's `build.install.bin` table so luarocks installs it
  to the system bin path.
- `copas.loop()` returns when all threads and sockets are done. Busted's
  test suite runs as a single Copas thread; the loop drains cleanly once it
  finishes.
- If busted calls `os.exit` directly (e.g. on a fatal parse error) the
  process exits before `copas.loop()` returns — this is acceptable, as it is
  not a test result.
- The script has no dependency on `copas.busted` (the helper module) and
  works standalone. Adopting projects get the runner for free just by
  installing the rock; the helper utilities are opt-in.

---

## 2. The Helper Module — `src/copas/busted.lua`

Users `require "copas.busted"` inside spec files to access assertion-safe
async utilities.

```lua
-------------------------------------------------------------------------------
-- copas.busted — helper utilities for testing Copas-based code with Busted.
--
-- @module copas.busted
-- @copyright 2024 Tieske
-- @license MIT
-------------------------------------------------------------------------------

local copas = require "copas"
local M = {}

-- Re-export copas.pause so tests can import a single module.
--- Suspend the current test coroutine for `seconds` seconds.
-- @tparam number seconds
M.pause = copas.pause


--- Wait until `condition()` returns truthy, then return.
-- Polls every `interval` seconds (default 0.05). Raises an error if
-- `timeout` seconds elapse first (default 5).
-- @tparam function condition  called repeatedly; done when it returns truthy
-- @tparam[opt=5]    number timeout   seconds before failure
-- @tparam[opt=0.05] number interval  polling interval in seconds
-- @usage
--   local result
--   start_async_operation(function(r) result = r end)
--   copas_busted.wait(function() return result ~= nil end, 3)
--   assert.equals("expected", result)
function M.wait(condition, timeout, interval)
  timeout  = timeout  or 5
  interval = interval or 0.05
  local deadline = copas.gettime() + timeout
  while not condition() do
    if copas.gettime() >= deadline then
      error(("Timeout: condition not met within %.2f seconds"):format(timeout), 2)
    end
    copas.pause(interval)
  end
end


--- Run `fn` and fail the test if it takes longer than `seconds`.
-- Internally schedules a Copas timer that raises an error in the calling
-- coroutine if the deadline is exceeded.
-- @tparam number   seconds  maximum allowed runtime
-- @tparam function fn       the test body (called synchronously in terms of
--                           coroutine flow, but yields to Copas while waiting)
-- @tparam[opt]     string   msg  error message prefix
-- @usage
--   copas_busted.timeout(5, function()
--     local data = copas.receive(socket)
--     assert.equals("hello", data)
--   end)
function M.timeout(seconds, fn, msg)
  msg = msg or ("Test timed out after %.2f seconds"):format(seconds)
  local co = coroutine.running()
  assert(co, "M.timeout must be called from within a coroutine (i.e. a Busted test)")

  local timed_out = false
  local timer = copas.timer.new({
    delay    = seconds,
    recurring = false,
    callback = function()
      timed_out = true
      -- Resume the test coroutine with an error.
      -- copas uses coroutine.resume internally; injecting an error here
      -- surfaces it at the next yield point inside fn.
      -- The safe approach: set a flag and let wait() or pause() propagate it.
    end,
  })

  -- Run fn; check timed_out at each cooperative yield by monkey-patching
  -- copas.pause for the duration. Simpler alternative: use a wrapper that
  -- checks after fn returns.
  local ok, err = pcall(fn)
  timer:cancel()

  if timed_out then
    error(msg, 2)
  end
  if not ok then
    error(err, 2)
  end
end


--- Assert that a function raises an error within `seconds`.
-- Useful for testing server rejection / protocol errors.
-- @tparam number   seconds
-- @tparam function fn
-- @treturn string  the error message that was raised
function M.assert_error_timeout(seconds, fn)
  local ok, err = pcall(M.timeout, seconds, fn)
  assert(not ok, "Expected an error but none was raised")
  return err
end


return M
```

### Timeout implementation note

The `M.timeout` function above has a known subtlety: a Copas timer fires in a
**separate** Copas thread, not in the test coroutine. You cannot directly
`error()` into another coroutine from a timer callback. The recommended
implementation strategy:

**Option A — polling flag (simplest, slight latency)**

The timer sets `timed_out = true`. A thin wrapper replaces `copas.pause`
inside `fn`'s scope so every yield checks the flag:

```lua
function M.timeout(seconds, fn, msg)
  msg = msg or ("timed out after %.2fs"):format(seconds)
  local timed_out = false

  local timer = copas.timer.new({
    delay = seconds, recurring = false,
    callback = function() timed_out = true end,
  })

  -- Shadow copas.pause so that every voluntary yield checks the flag.
  local real_pause = copas.pause
  copas.pause = function(t)
    real_pause(t)
    if timed_out then error(msg, 0) end
  end

  local ok, err = pcall(fn)
  copas.pause = real_pause
  timer:cancel()

  if not ok and not timed_out then
    -- propagate original error
    error(err, 2)
  end
  if timed_out then
    error(msg, 2)
  end
end
```

**Option B — separate timeout thread (precise)**

Spawn a copas thread that sleeps for `seconds` and then sets a shared
table's `error` field, which the main test thread checks via `M.wait`.
This is more complex but avoids monkey-patching.

Implement Option A first; switch to Option B if precision matters.

---

## 3. Rockspec — `busted-copas-scm-1.rockspec`

```lua
rockspec_format = "3.0"
package = "busted-copas"
version = "scm-1"

source = {
  url = "git+https://github.com/Tieske/busted-copas.git",
}

description = {
  summary  = "Busted test runner and helpers for asynchronous Copas-based applications",
  detailed = [[
    busted-copas wraps the Busted test runner inside a Copas coroutine loop,
    enabling tests of async Copas code to be written with no special syntax.
    It also provides helper utilities for condition-waiting and per-test timeouts.
  ]],
  license  = "MIT",
  homepage = "https://github.com/Tieske/busted-copas",
}

dependencies = {
  "lua >= 5.1",
  "copas >= 4.0.0",
  "busted >= 2.1",
}

build = {
  type = "builtin",
  modules = {
    ["copas.busted"] = "src/copas/busted.lua",
  },
  install = {
    bin = {
      ["busted-copas"] = "bin/busted-copas",
    },
  },
}
```

Adjust the `copas` version floor to match what `copas.timer` and
`copas.gettime` were introduced (verify against the copas changelog).

---

## 4. `.busted` Configuration

### For adopting projects

After `luarocks install busted-copas`, the adopting project adds a single
line to its `.busted`:

```lua
-- .busted (in the adopting project's root)
return {
  default = {
    lua      = "busted-copas",
    verbose  = true,
    coverage = false,
    output   = "gtest",
  },
}
```

From that point on, `busted` (plain, unchanged) runs the full suite inside
Copas. No CLI wrapper, no script to copy, no other changes needed.

### For this library's own tests

The library's own `.busted` does the same, since the helper-module tests
(`02-helpers_spec.lua`) need Copas running:

```lua
-- busted-copas/.busted
return {
  default = {
    lua     = "busted-copas",
    verbose = true,
    output  = "gtest",
  },
}
```

During development (before the rock is installed to PATH), the `lua` value
can be set to the relative path `"bin/busted-copas"` so the test suite can
be run from the repo without a prior `luarocks make`.

---

## 5. Tests for the Library Itself — `spec/`

### `spec/01-runner_spec.lua`

Tests that `busted-copas` (the CLI) can be invoked as a subprocess and
produces the expected exit code for passing and failing suites.

```lua
-- These are synchronous tests (no copas needed); they shell out to the CLI.

local function run(args)
  -- Shell out to busted, which uses spec/copas-runner.lua via .busted config.
  -- Returns exit code and stdout.
  local cmd = "busted " .. args .. " 2>&1; echo EXIT:$?"
  local out = io.popen(cmd):read("*a")
  local code = tonumber(out:match("EXIT:(%d+)"))
  return code, out
end

describe("busted-copas runner", function()

  it("exits 0 when all tests pass", function()
    local code = run("spec/fixtures/passing_spec.lua")
    assert.equals(0, code)
  end)

  it("exits 1 when a test fails", function()
    local code = run("spec/fixtures/failing_spec.lua")
    assert.equals(1, code)
  end)

  it("supports standard busted flags (e.g. --pattern)", function()
    local code = run("--pattern=passing spec/fixtures/")
    assert.equals(0, code)
  end)

end)
```

Create the fixtures:

**`spec/fixtures/passing_spec.lua`**
```lua
local copas = require "copas"
describe("fixture: passing", function()
  it("pauses briefly and passes", function()
    copas.pause(0.01)
    assert.is_true(true)
  end)
end)
```

**`spec/fixtures/failing_spec.lua`**
```lua
describe("fixture: failing", function()
  it("always fails", function()
    assert.is_true(false)
  end)
end)
```

### `spec/02-helpers_spec.lua`

Run these with `busted-copas` so they execute inside the Copas loop.

```lua
local cb = require "copas.busted"
local copas = require "copas"

describe("copas.busted.wait()", function()

  it("returns when condition becomes true", function()
    local flag = false
    copas.addthread(function()
      copas.pause(0.05)
      flag = true
    end)
    cb.wait(function() return flag end, 2)
    assert.is_true(flag)
  end)

  it("raises an error on timeout", function()
    assert.has_error(function()
      cb.wait(function() return false end, 0.1, 0.02)
    end)
  end)

end)

describe("copas.busted.timeout()", function()

  it("passes when fn completes in time", function()
    cb.timeout(2, function()
      copas.pause(0.05)
    end)
  end)

  it("raises an error when fn takes too long", function()
    assert.has_error(function()
      cb.timeout(0.1, function()
        copas.pause(1)
      end)
    end)
  end)

end)

describe("copas.busted.pause()", function()
  it("is an alias for copas.pause", function()
    assert.equals(copas.pause, cb.pause)
  end)
end)
```

---

## 6. Luacheck Configuration — `.luacheckrc`

Start from the template's default and add busted globals:

```lua
std = "lua51+lua52+lua53+lua54"
globals = {}
read_globals = {
  -- busted
  "describe", "it", "pending", "before_each", "after_each",
  "before_all", "after_all", "setup", "teardown",
  "assert", "spy", "stub", "mock",
  -- lua
  "unpack",
}
files["spec/**"] = { std = "lua51+lua52+lua53+lua54" }
```

---

## 7. LDoc Config — `config.ld`

```lua
project        = "busted-copas"
title          = "busted-copas documentation"
description    = "Busted helpers for async Copas testing"
dir            = "docs"
file           = { "src/" }
style          = "!fixed"
module_list    = { "copas.busted" }
not_luadoc     = true
use_markdown_titles = true
```

---

## 8. CI — `.github/workflows/ci.yml`

Extend the template's CI to install `copas` and `busted` before running
tests. The matrix should cover Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT.

Key CI steps (inside the existing template's structure):

```yaml
- name: Install dependencies
  run: |
    luarocks install copas
    luarocks install busted
    luarocks make busted-copas-scm-1.rockspec

- name: Run tests
  run: busted

- name: Luacheck
  run: luacheck src/ spec/
```

A single `busted` invocation suffices because `.busted` sets `lua =
"spec/copas-runner.lua"` for all tests. The runner-integration tests shell
out to `busted` as a subprocess internally, so they work under the same
configuration.

---

## 9. Makefile Targets

Add to the template's Makefile:

```makefile
test:
	busted

lint:
	luacheck src/ spec/

docs:
	ldoc .
```

---

## 10. README Content (summary for the agent)

The README should cover:

1. **Installation**: `luarocks install busted-copas`
2. **Setup**: add `lua = "busted-copas"` to the project's `.busted` config.
   Run tests as usual with `busted` — no other change needed.
3. **Why it works**: one-paragraph explanation of the inverted control model.
4. **Helper API**: document `pause`, `wait`, `timeout` with examples.
5. **Example test**: a realistic Copas TCP client/server round-trip test.
6. **Compatibility**: Lua 5.1–5.5, LuaJIT; Copas ≥ 4.0; Busted ≥ 2.1.
7. **Limitations** section (see below).

### Realistic example test (for README)

```lua
-- spec/echo_server_spec.lua
-- Run with: busted-copas spec/echo_server_spec.lua

local copas  = require "copas"
local socket = require "socket"
local cb     = require "copas.busted"

local PORT = 19876

describe("echo server", function()
  local server

  before_each(function()
    -- Start a trivial TCP echo server as a Copas thread.
    server = assert(socket.bind("127.0.0.1", PORT))
    copas.addserver(server, function(skt)
      skt = copas.wrap(skt)
      local line = skt:receive("*l")
      skt:send(line .. "\n")
    end)
  end)

  after_each(function()
    server:close()
  end)

  it("echoes a line back to the client", function()
    local received
    copas.addthread(function()
      local client = copas.wrap(assert(socket.connect("127.0.0.1", PORT)))
      client:send("hello\n")
      received = client:receive("*l")
      client:close()
    end)

    -- Wait for the client thread to populate `received`.
    cb.wait(function() return received ~= nil end, 5)
    assert.equals("hello", received)
  end)

end)
```

---

## 11. Known Limitations & Open Questions

1. **`arg` table layout**: The exact indices busted uses when invoking a
   custom `--lua` script may vary by busted version. Verify by adding a
   temporary `print` of the full `arg` table in `copas-runner.lua` before
   the `dofile` call. Adjust the shift logic if needed.

2. **`os.exit` from busted**: If busted calls `os.exit` directly (e.g. on a
   fatal parse error), the process exits before `copas.loop()` returns. This
   is acceptable — a fatal error isn't a test result. Verify with a
   deliberately broken spec file.

3. **`copas.timer` availability**: `M.timeout` depends on `copas.timer`. This
   was introduced in Copas 3.x. Verify the minimum required version and
   update the rockspec dependency accordingly. If the target Copas is older,
   implement the timer using `copas.addthread` + `copas.pause` instead.

4. **`copas.gettime`**: Used in `M.wait`. Available since Copas 3.x. Same
   check as above; fall back to `socket.gettime()` (from LuaSocket) if
   unavailable.

5. **Parallel test execution**: Busted runs tests sequentially within a
   single coroutine (the runner thread). Tests that `copas.addthread()` spawn
   sub-tasks must use `cb.wait()` to synchronise before the test ends, or
   those threads will run during a later test, causing interference. Document
   this clearly.

6. **Test isolation for Copas state**: Copas maintains a global scheduler
   state (registered servers, timers, threads). If a test leaks threads
   (e.g., a server not closed in `after_each`), subsequent tests may see
   unexpected traffic. Document the expectation that each test cleans up its
   own Copas resources in `after_each`.

7. **Copas error handler**: Copas has a global error handler
   (`copas.seterrorhandler`). If a test thread errors in a way that bypasses
   busted's `xpcall`, it surfaces in the Copas error handler rather than as a
   test failure. Consider setting the Copas error handler in the runner to
   forward unhandled thread errors to busted's failure mechanism. This is an
   enhancement for a future version; document it as a known gap.

---

## Implementation Order

1. Confirm the repo has been bootstrapped from `Tieske/project.lua` by the project owner (do not create or clone the repo — start from the existing scaffold).
2. Implement `bin/busted-copas`; mark it executable. Verify the `arg` table
   layout by printing it when invoked via `busted --lua=bin/busted-copas` on
   a trivial spec file. Adjust the shift logic if needed.
3. Configure `.busted` with `lua = "bin/busted-copas"` (relative path for
   development; the README instructs adopters to use `"busted-copas"` after
   installation).
4. Implement `src/copas/busted.lua` (start with `pause` and `wait`; add
   `timeout` once the simpler helpers are tested).
5. Write fixture files under `spec/fixtures/`.
6. Write `spec/01-runner_spec.lua` and verify exit codes.
7. Write `spec/02-helpers_spec.lua` and run with plain `busted`.
8. Configure Luacheck, LDoc, CI.
9. Write README with the echo server example and the setup instructions.
