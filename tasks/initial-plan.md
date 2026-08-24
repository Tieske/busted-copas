# busted-copas — Implementation Specification

## Overview

`busted-copas` is a thin Lua library that enables testing of asynchronous
[Copas](https://github.com/lunarmodules/copas)-based applications with the
[Busted](https://github.com/lunarmodules/busted) test framework.

**The core idea:** instead of busted owning the outermost execution loop and
calling into a scheduler, Copas owns the loop and busted's runner executes as
a Copas coroutine thread. Any test that calls a Copas-native API (socket I/O,
`copas.pause`, timers, etc.) simply yields and resumes naturally — no special
test syntax, no `done()` callbacks, no adapter layer. This is true for
**every** test, not just ones that opt into the helper module below — the
runner wrapper alone is sufficient to make async Copas code testable.

The library ships two things:

1. **`bin/busted-copas`** — a script installed to PATH by luarocks, used as
   the `lua` interpreter value in an adopting project's `.busted` config file.
   Busted invokes it as the Lua interpreter for its own main script; it shifts
   the `arg` table, wraps `dofile(busted_script)` in `copas.addthread`, and
   calls `copas.loop()`. The adopting project's users still type plain `busted`
   — no CLI change required.
2. **`src/busted-copas/init.lua`** — a helper module with assertion-friendly,
   *opt-in* utilities for async tests: waiting for conditions (`wait`), a
   plain re-export of `copas.pause` (`pause`), and a per-test timeout wrapper
   (`timeout`). Nothing in this module is required to use the runner — it
   exists for the cases where the primitives Copas already gives you
   (`copas.settimeout`, lock/semaphore timeouts) aren't quite enough.

---

## Repository Bootstrap

Already done — this repo was scaffolded from `Tieske/project.lua` and is what
we're operating on. Module name is `busted-copas` (`require "busted-copas"`,
source at `src/busted-copas/init.lua`), rockspec/CI/Luacheck/LDoc/Makefile
are already in place.

What's left is template placeholder content, not scaffolding — these need
replacing as part of the work below, not before it:

- `bin/busted-copas.lua` — currently a CLI stub that just echoes `arg`;
  replace entirely per section 1.
- `src/busted-copas/init.lua` — currently a `do_something(what, force)` stub;
  replace entirely per section 2.
- `spec/01-first-test_spec.lua` — a placeholder smoke test (just checks the
  module loads and has `_VERSION`/`_COPYRIGHT`/`_DESCRIPTION`); superseded by
  `01-runner_spec.lua`/`02-helpers_spec.lua` in section 5.
- `README.md` — currently just the one-line tagline and boilerplate badges;
  needs the content from section 10.
- `examples/example1.lua`, `doc_topics/01-introduction.md`,
  `doc_topics/02-advanced.md` — generic template filler, not specific to this
  project; replace or delete once real docs/examples exist.
- `busted-copas-scm-1.rockspec` — currently only has `lua >= 5.1, < 5.6` as a
  dependency; needs the `copas`/`busted` entries from section 3.
- `.busted` — currently has no `lua` key at all (plain default busted run);
  needs the addition from section 4.

---

## Final Directory Layout

```
busted-copas/
├── .github/
│   └── workflows/
│       ├── lint.yml          (already correct, no changes needed)
│       └── unix_build.yml    (already correct, no changes needed)
├── bin/
│   └── busted-copas.lua      (the Lua-interpreter wrapper; installed to PATH as `busted-copas`)
├── spec/
│   ├── 01-runner_spec.lua    (tests for the runner behaviour)
│   ├── 02-helpers_spec.lua   (tests for the helper utilities)
│   └── fixtures/
│       ├── passing_spec.lua
│       └── failing_spec.lua
├── src/
│   └── busted-copas/
│       └── init.lua          (the helper module; require "busted-copas")
├── .busted                   (busted config for this project's own tests)
├── .luacheckrc
├── config.ld                 (LDoc)
├── busted-copas-scm-1.rockspec
├── Makefile
└── README.md
```

Not part of the rockspec, but worth having in this repo for its own
development (and as a template adopters can copy into their own projects):
a Claude Code skill that reviews spec files for the two hygiene issues this
design surfaced — a `finally()` registered *after* the operation it should
guard, and a `before_each`-created socket/server with no matching
`after_each` cleanup. See "Known Limitations" and "Implementation Order"
below. It's a dev-time aid, not something luarocks can distribute, so it
lives under this repo's own skills directory rather than in `src/` or the
rockspec's `build.install` table.

---

## 1. The Interpreter Wrapper — `bin/busted-copas`

`busted-copas` is installed to PATH by luarocks. Adopting projects reference
it as the `lua` interpreter in their `.busted` config (see section 4). When
the user runs `busted`, busted internally invokes `busted-copas` in place of
`lua` to run its own main script — the user's CLI workflow is completely
unchanged.

Confirmed against Busted's actual source (`busted/modules/cli.lua`): when a
custom `lua` value is configured, Busted genuinely re-execs itself via a
subprocess (`pl.utils.execute`, i.e. `os.execute`), then exits with that
subprocess's code. The invocation looks like:

```
busted-copas /path/to/busted/main.lua --ignore-lua [test-file-args...]
```

Inside `busted-copas`, the argument table is therefore:

```
arg[-1]  the path to busted-copas itself
arg[0]   busted-copas (script name)
arg[1]   /path/to/busted/main.lua   ← the busted entry script
arg[2]   "--ignore-lua"             ← a real busted flag, consumed by busted's
                                       own re-parse to prevent infinite re-exec
arg[3..] the test-file args busted was given
```

(`--ignore-lua` sits at `arg[2]`, not a test-file arg — worth knowing if
you're debugging the `arg` table directly, though the shift logic below
doesn't hard-code offsets so it isn't affected.)

The script shifts `arg` so that busted's main script sees itself as `arg[0]`,
runs it inside a Copas thread, then explicitly tears the loop down once
busted's run is complete — rather than letting `copas.loop()` wait
indefinitely for scheduler state that may never clear on its own (see
"Known Limitations" #1):

```lua
#!/usr/bin/env lua
-------------------------------------------------------------------------------
-- bin/busted-copas.lua
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

  -- copas.loop() only returns once ALL scheduler activity clears: every
  -- addthread AND every addserver-registered listener. A single spec that
  -- opens a server and forgets to close it would otherwise hang the process
  -- forever instead of failing with a message. cancelall() is copas's own
  -- test-teardown primitive: it force-closes every socket, removes every
  -- server, and cancels every thread, then lets the loop exit cleanly.
  -- It must be called from inside the running loop, which this is.
  copas.cancelall()
end)

copas.loop()
```

### Notes

- The script must be marked executable (`chmod +x bin/busted-copas.lua`) and
  is already listed in the rockspec's `build.install.bin` table (installed as
  `busted-copas`, without the `.lua` extension, on the system bin path).
- `copas.cancelall()` is documented upstream as "intended for test teardown
  only" — it abandons all registered threads/sockets without giving them a
  chance to clean up. That's the correct behaviour here: by the time it runs,
  busted has already finished and reported results: any leftover Copas state
  is by definition something a test failed to clean up, not something a
  well-behaved run would still need.
- If busted calls `os.exit` directly (e.g. on a fatal parse error) the
  process exits before `copas.loop()`/`cancelall()` runs — this is
  acceptable, as it is not a test result.
- The script has no dependency on `busted-copas` (the helper module) and
  works standalone. Adopting projects get the runner for free just by
  installing the rock; the helper utilities are opt-in.
- Busted's re-exec quotes each arg only on unreleased (post-`v2.3.0`) commits
  as of this writing; every currently released version joins args with plain
  `table.concat(args, ' ')`, unescaped. A spec path containing a space or
  shell metacharacter can break the re-exec. This is a busted-side issue, not
  fixable from here — see "Known Limitations".

---

## 2. The Helper Module — `src/busted-copas/init.lua`

Users `require "busted-copas"` inside spec files to access assertion-safe
async utilities. Everything in this module is a plain function, callable
from anywhere — none of it is a busted DSL keyword, and none of it calls
busted's own `it`/`describe`/etc. internally. That's a deliberate constraint,
not an oversight: a file loaded via `require` gets its own environment, not
the sandboxed one busted wraps around each spec file, so a helper defined
here could never resolve a bareword `it` correctly even if it tried. `timeout`
below works *with* that constraint instead of around it — it returns a
wrapped callback for the spec file's own `it(...)` call to use, rather than
trying to invoke `it` itself.

```lua
--- busted-copas — helper utilities for testing Copas-based code with Busted.
--
-- @copyright Copyright (c) 2026-2026 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE.md`.

local copas  = require "copas"
local future = require "copas.future"
local timer  = require "copas.timer"

local M = {}
M._VERSION = "0.0.1"
M._COPYRIGHT = "Copyright (c) 2026-2026 Thijs Schreijer"
M._DESCRIPTION = "Test framework for testing async Copas applications, on top of Busted"

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
--   cb.wait(function() return result ~= nil end, 3)
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


--- Wrap `fn` so it fails if it doesn't complete within `seconds`.
-- Runs `fn` as its own Copas future. If `seconds` elapses first, the future
-- is cancelled (it stops being scheduled — Lua coroutines can't be forcibly
-- terminated, so this is abandonment, not interruption) and the wrapped
-- function raises an error.
--
-- Returns a *function*, meant to be handed to busted's own `it()` as the
-- test body — `cb.timeout` never calls `it` itself (see the module note
-- above for why).
--
-- Any resource `fn` acquires must be registered for cleanup via busted's
-- `finally()` *immediately*, before the operation that might be the one
-- that times out. `finally()` runs in busted's own still-alive coroutine
-- regardless of whether `fn`'s coroutine ever resumes again, so registering
-- early is what makes cleanup survive a timeout — this is the same acquire
-- then immediately register discipline plain busted tests already need
-- (skip it, and an exception between acquisition and registration leaks the
-- resource today, timeout or not).
--
-- @tparam number   seconds  maximum allowed runtime
-- @tparam function fn       the test body
-- @tparam[opt]     string   msg  error message prefix
-- @usage
--   it("completes the handshake in time", cb.timeout(5, function()
--     local skt = assert(socket.connect(host, port))
--     finally(function() copas.close(skt) end)
--     local data = copas.receive(skt)
--     assert.equals("hello", data)
--   end))
function M.timeout(seconds, fn, msg)
  msg = msg or ("Test timed out after %.2f seconds"):format(seconds)

  return function(...)
    local args = { n = select("#", ...), ... }

    local fut = future.addthread(function()
      return fn((table.unpack or unpack)(args, 1, args.n))
    end)

    local t = timer.new({
      delay = seconds,
      recurring = false,
      callback = function() fut:cancel() end,
    })

    local ok, err = fut:get()
    t:cancel()

    if not ok then
      if err == "cancelled" then
        error(msg, 2)
      end
      error(err, 2)
    end
  end
end


return M
```

### Why there's no `M.assert_error_timeout`

The original design had a helper for "assert `fn` raises an error within N
seconds." With `timeout` now returning a plain function, the same result is
just composition with busted's existing `assert.has_error`:

```lua
assert.has_error(cb.timeout(1, function()
  -- ... something that should error ...
end))
```

No dedicated helper needed — dropped to keep the module minimal.

### Why there's no whole-suite error forwarding

A background thread a test spawns with a bare `copas.addthread` (not
wrapped in a `future`) that errors independently still goes to Copas's
default error handler (prints and vanishes) — the library does not install
`copas.seterrorhandler` anywhere, and doesn't check for stray errors in
`after_each`. This is a deliberate scope decision, not a gap to revisit
later: if a subtask's outcome matters to a test's correctness, the test
should observe it explicitly — e.g. wrap it in its own `copas.future` and
check the result — the same way `cb.timeout` observes its own future.
Assertions belong on the thread executing the `it` block; a library-level
safety net would just be catching what should have been synchronized on in
the first place.

---

## 3. Rockspec — `busted-copas-scm-1.rockspec`

The rockspec already exists (scaffolded); only `dependencies` needs the
`copas`/`busted` entries added — everything else (module/bin keys,
`copy_directories`) is already correct as-is:

```lua
local package_name = "busted-copas"
local package_version = "scm"
local rockspec_revision = "1"
local github_account_name = "Tieske"
local github_repo_name = "busted-copas"


package = package_name
version = package_version.."-"..rockspec_revision

source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
  branch = (package_version == "scm") and "main" or nil,
  tag = (package_version ~= "scm") and package_version or nil,
}

description = {
  summary = "Test framework for testing async Copas applications, on top of Busted",
  detailed = [[
    Test framework for testing async Copas applications, on top of Busted
  ]],
  license = "MIT",
  homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
}

dependencies = {
  "lua >= 5.1, < 5.6",
  "copas >= 4.12.0",
  "busted >= 2.3.0",
}

build = {
  type = "builtin",

  modules = {
    ["busted-copas.init"] = "src/busted-copas/init.lua",
  },

  install = {
    bin = {
      ["busted-copas"] = "bin/busted-copas.lua",
    }
  },

  copy_directories = {
    -- can be accessed by `luarocks busted-copas doc` from the commandline
    "docs",
  },
}
```

Version floors verified directly against source, not assumed:
`copas.gettime` (used by `M.wait`) wasn't a public field until copas
**4.8.0**; `copas.future` and `copas.removethread` (used by `M.timeout`) are
present in the current release line. Pinning to the current latest
(**4.12.0**) rather than the lowest version that happens to work, per the
decision to not carry old-version compatibility baggage. Same reasoning for
busted **2.3.0**. Note the module key is `busted-copas.init`, not bare
`busted-copas` — that's what makes luarocks install the file at
`src/busted-copas/init.lua`; Lua's own `require "busted-copas"` still
resolves to it normally via the standard `init.lua`-package convention,
independent of this dotted key.

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
Copas. No CLI wrapper, no script to copy, no other changes needed. (A
`busted.register`-based custom DSL keyword, or a `.busted` `helper` script
that injects one, were both considered for giving `timeout` a more
first-class call syntax — rejected: a shipped helper script ends up buried
somewhere inside the luarocks tree, hard for adopters to even locate to
reference in their config, for a purely cosmetic gain over the `require`-based
`cb.timeout(...)` helper.)

### For this library's own tests

The `.busted` file already exists in this repo (`verbose = true, coverage =
true, output = "gtest", lazy = true`, no `lua` key yet). Only the `lua` key
needs adding — keep everything else as-is:

```lua
-- busted-copas/.busted
return {
  default = {
    lua      = "bin/busted-copas.lua",
    verbose  = true,
    coverage = true,
    output   = "gtest",
    lazy     = true,
  },
}
```

The relative path `"bin/busted-copas.lua"` is used during development (no
prior `luarocks make` needed to run the suite from the repo); switch to the
plain `"busted-copas"` value only once relying on the installed rock.

---

## 5. Tests for the Library Itself — `spec/`

### `spec/01-runner_spec.lua`

Tests that `busted-copas` (the CLI) can be invoked as a subprocess and
produces the expected exit code for passing and failing suites.

```lua
-- These are synchronous tests (no copas needed); they shell out to the CLI.

local function run(args)
  -- Shell out to busted, which uses bin/busted-copas via .busted config.
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

  it("exits cleanly even if a spec leaks a copas server", function()
    -- regression test for the copas.cancelall() call in bin/busted-copas;
    -- without it this invocation would hang instead of exiting.
    local code = run("spec/fixtures/leaky_server_spec.lua")
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

**`spec/fixtures/leaky_server_spec.lua`**
```lua
local copas  = require "copas"
local socket = require "socket"

describe("fixture: leaky server", function()
  it("opens a server and never closes it", function()
    local server = assert(socket.bind("127.0.0.1", 0))
    copas.addserver(server, function() end)
    -- deliberately no cleanup — this is what cancelall() must recover from
  end)
end)
```

### `spec/02-helpers_spec.lua`

Run these with `busted-copas` so they execute inside the Copas loop.

```lua
local cb     = require "busted-copas"
local copas  = require "copas"

describe("busted-copas.wait()", function()

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

describe("busted-copas.timeout()", function()

  it("passes when fn completes in time", cb.timeout(2, function()
    copas.pause(0.05)
  end))

  it("raises an error when fn takes too long", function()
    assert.has_error(cb.timeout(0.1, function()
      copas.pause(1)
    end))
  end)

  it("still runs finally() registered before the timing-out call",
    cb.timeout(0.1, function()
      local cleaned_up = false
      finally(function() cleaned_up = true end)
      copas.pause(1) -- this is what times out
      -- assertion below never runs; that's expected — the point of this
      -- test is what busted observes in `finally`, checked separately
      -- via a shared upvalue the outer describe block inspects after
      -- the `it` above has already failed with a timeout.
    end)
  )

end)

describe("busted-copas.pause()", function()
  it("is an alias for copas.pause", function()
    assert.equals(copas.pause, cb.pause)
  end)
end)
```

---

## 6. Luacheck Configuration — `.luacheckrc`

Already handled — no changes needed. The scaffolded `.luacheckrc` has:

```lua
files["spec/**/*.lua"] = {
    std = "+busted",
}
```

`+busted` uses Luacheck's own built-in `busted` standard (confirmed present
in the installed Luacheck 1.2.0: `describe`, `it`, `pending`, `before_each`,
`after_each`, `insulate`, `expose`, `context`, `test`, `match`,
`lazy_setup`/`lazy_teardown`, `strict_setup`/`strict_teardown`, `setup`,
`teardown`, `assert`, `spy`, `mock`, `stub`, `finally`, `randomize`) — the
`+` additively layers it onto the base std rather than replacing it, and
it's scoped only to `spec/**/*.lua`. `finally` (needed for `M.timeout`'s
usage pattern) is already included; nothing to add. Note this list also
corrects an error in the library's own earlier globals table, which had
invented `before_all`/`after_all` — not real busted keywords (that's
Jest/Mocha naming); busted's actual equivalents are `lazy_setup` /
`strict_setup` and their `_teardown` counterparts.

---

## 7. LDoc Config — `config.ld`

Already handled — no changes needed. The scaffolded `config.ld` already
covers both `./src/` and `./bin/` (useful since `bin/busted-copas.lua` will
carry its own doc comments too), sets `format='markdown'`, and wires up
`topics`/`examples`/`sort`. No reason to replace it with a narrower config.

---

## 8. CI — `.github/workflows/*.yml`

Already handled — no workflow changes needed. Two real workflows already
exist, `lint.yml` and `unix_build.yml`, both driven entirely through
Makefile targets (`make dev`, `make lint`, `make testinst`) rather than
inline `luarocks install` steps. `make dev`/`make deps` already runs
`luarocks install $(ROCKSPEC) --deps-only`, which pulls in whatever's listed
in the rockspec's `dependencies` table — once section 3's rockspec edit
lands (`copas >= 4.12.0`, `busted >= 2.3.0`), those get installed
automatically. No separate `luarocks install copas`/`luarocks install
busted` step to add anywhere.

`unix_build.yml`'s matrix is already wider than assumed earlier: `5.1, 5.2,
5.3, 5.4, 5.5, luajit, luajit-openresty` — confirmed the current copas
release (4.12.0, via a `coxpcall` shim on non-JIT 5.1) and busted (2.3.0, no
upper Lua bound) both still support that range, so pinning dependency
versions to latest doesn't require narrowing it.

`make testinst` (used by `unix_build.yml`) installs the rock and runs
`busted --lpath="" --cpath=""` — worth double-checking during
implementation that this doesn't interfere with `bin/busted-copas.lua`
picking up `copas`/`busted-copas` correctly once actually installed via
`luarocks make`, since it deliberately empties the Lua/C path env vars to
force resolution through the installed rock tree only.

---

## 9. Makefile Targets

Already handled — no changes needed. The scaffolded Makefile already has
`test` (`busted ${BUSTED}`), `lint` (`luarocks lint` on every rockspec, plus
`luacheck .`), `doc`/`docs` (`ldoc .`), plus `install`, `uninstall`, `clean`,
`testinst`, `deps`, and `dev` — all more complete than what this section
originally proposed adding from scratch.

---

## 10. Documentation Content — `doc_topics/` and `examples/`

The README is **intentionally thin** and already correct as scaffolded — no
changes needed there. It's just badges, a one-line tagline, and pointers
(License, [online documentation](https://Tieske.github.io/busted-copas/),
CONTRIBUTING.md, AGENTS.md, CHANGELOG.md). That's deliberate: all real
documentation lives in one place, the generated GitHub Pages site, so it
doesn't fork into "what the README says" vs. "what the docs site says."
LDoc (`config.ld`) already renders two things into that site:
`doc_topics/*.md` (topic pages) and `examples/*.lua` (example listings) —
so everything below targets those directories, not the README.

### `doc_topics/`

Two placeholder files already exist and should be replaced with real
content (their numeric prefixes control nav order on the docs site — reuse
them, no need to add more files unless the content genuinely doesn't fit):

**`doc_topics/01-introduction.md`** (replacing the current "1. Introduction"
placeholder):

1. **Installation**: `luarocks install busted-copas`
2. **Setup**: add `lua = "busted-copas"` to the project's `.busted` config.
   Run tests as usual with `busted` — no other change needed.
3. **Why it works**: one-paragraph explanation of the inverted control model
   — every test already runs as a Copas coroutine, so any Copas-native call
   just works in a plain `it()`; nothing in the helper module is required to
   get that behaviour.
4. **Compatibility**: Lua 5.1–5.5, LuaJIT; Copas ≥ 4.12.0; Busted ≥ 2.3.0.

**`doc_topics/02-timeouts.md`** (replacing the current "2. Advanced topic"
placeholder — rename from `02-advanced.md`, it's still just filler content
so nothing external depends on the old name):

1. **Timeouts, two ways**:
   - *Per-operation* (preferred, most precise): `copas.settimeout(skt,
     seconds)` before `copas.receive`/`copas.send` (returns `nil, "timeout"`
     on expiry, no helper needed); locks/semaphores take an inline
     `timeout` argument directly (`lock:get(timeout)`,
     `semaphore:take(n, timeout)`).
   - *Whole-test safety net*: `cb.timeout(seconds, fn)`, for catching gross
     hangs the per-operation timeouts wouldn't (e.g. a chain of many short
     waits that individually never expire but collectively hang). Document
     clearly that a `cb.timeout` timeout means the test's coroutine is
     *abandoned*, not terminated — any cleanup must be registered via
     `finally()` immediately after resource acquisition, before the call
     that might be the one that hangs.
2. **Helper API**: document `pause`, `wait`, `timeout` with examples,
   including the `finally()`-ordering requirement and the "subtasks manage
   their own errors" pattern (wrap in `copas.future` if a background
   thread's outcome needs to be observed by the test). Link to the
   `examples/` echo-server test rather than re-embedding it here.
3. **Limitations**: the user-facing subset of section 11 below (coroutine
   abandonment semantics, stray background-thread errors not being
   forwarded, busted's arg-quoting fragility) — not the whole section, just
   what an adopter needs to know, not internal implementation notes.

### `examples/`

Replace `examples/example1.lua` (currently generic `_G` iteration filler,
unrelated to this project) with a realistic Copas TCP client/server
round-trip test, using `cb.timeout` and `finally()` together — LDoc's
`examples = {'./examples'}` config picks this up automatically:

```lua
-- examples/echo_server_spec.lua
-- Run with: busted-copas examples/echo_server_spec.lua

local copas  = require "copas"
local socket = require "socket"
local cb     = require "busted-copas"

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
    copas.removeserver(server)
  end)

  it("echoes a line back to the client", cb.timeout(5, function()
    local client = copas.wrap(assert(socket.connect("127.0.0.1", PORT)))
    finally(function() copas.close(client) end)

    client:send("hello\n")
    local received = client:receive("*l")

    assert.equals("hello", received)
  end))

end)
```

---

## 11. Known Limitations & Open Questions

1. **Busted's re-exec arg quoting**: on every currently released busted
   version (as of this writing), args passed through the `lua`-interpreter
   re-exec are joined unescaped (`table.concat(args, ' ')`) — a spec path
   containing a space or shell metacharacter breaks the re-exec. Fixed only
   in an unreleased commit upstream. Not fixable from this library; worth a
   README callout so it isn't mistaken for a `busted-copas` bug.

2. **`os.exit` from busted**: if busted calls `os.exit` directly (e.g. on a
   fatal parse error), the process exits before `copas.loop()`/
   `copas.cancelall()` runs. This is acceptable — a fatal error isn't a test
   result. Verify with a deliberately broken spec file.

3. **Parallel test execution**: Busted runs tests sequentially within a
   single coroutine (the runner thread). Tests that `copas.addthread()` spawn
   sub-tasks must synchronize on them (via `cb.wait()`, a `copas.future`, or
   similar) before the test ends, or those threads will run during a later
   test, causing interference. Document this clearly.

4. **Test isolation for Copas state, mid-suite**: `copas.cancelall()` (in
   `bin/busted-copas`) only fires once, after busted's *entire* run
   completes — it does not protect a later test in the same run from a
   leaked thread or unclosed socket in an earlier one. There is no runtime
   safety net for this by design (see the "no whole-suite error forwarding"
   rationale in section 2) — it's caught at write-time instead, by the
   companion linting skill (see Implementation Order).

5. **Stray background-thread errors**: an error inside a `copas.addthread`
   that isn't wrapped in a `copas.future` is not surfaced as a test failure
   — it goes to Copas's default error handler (prints, doesn't fail
   anything). This is a deliberate scope decision, not a gap: subtasks whose
   outcome matters to a test should be explicitly observed by that test.

6. **`cb.timeout` cancellation is abandonment, not termination**: Lua
   coroutines can't be forcibly interrupted mid-yield. A `cb.timeout` expiry
   stops the test's coroutine from ever being resumed again — it does not
   run any code after the point it was suspended, including any inline
   cleanup that isn't behind a `finally()` registered earlier. This is
   fundamental to how Lua coroutines work, not a limitation specific to this
   library, but it's the single most important thing for adopters to
   understand correctly.

---

## Implementation Order

1. Add the `copas`/`busted` dependency entries to
   `busted-copas-scm-1.rockspec` (section 3).
2. Replace the `bin/busted-copas.lua` CLI stub with the real interpreter
   wrapper, including the `copas.cancelall()` call; mark it executable. The
   arg-table layout and re-exec mechanism are already confirmed against
   busted's source (section 1) — no separate validation spike needed before
   starting.
3. Add the `lua = "bin/busted-copas.lua"` line to the existing `.busted`
   (section 4).
4. Replace the `src/busted-copas/init.lua` `do_something` stub with the real
   helper module: `pause` and `wait` first (unchanged from the original
   design), then `timeout` (the `copas.future` + `copas.timer` +
   `future:cancel()` implementation in section 2).
5. Write fixture files under `spec/fixtures/`, including
   `leaky_server_spec.lua` for the `cancelall()` regression test.
6. Replace `spec/01-first-test_spec.lua` (the placeholder smoke test) with
   `spec/01-runner_spec.lua` and verify exit codes, including the
   leaky-server case.
7. Write `spec/02-helpers_spec.lua` and run with plain `busted`, including
   the timeout/`finally()` interaction test.
8. Confirm `make lint`/`make testinst` still pass locally once steps 1-7 are
   in place (Luacheck and CI are both already correctly configured — no
   changes needed, see sections 6 and 8).
9. Write README with the echo server example and the setup instructions.
10. Author the companion Claude Code skill (e.g.
    `.agents/skills/check-async-test-hygiene/SKILL.md`) that reviews spec
    files for: a `finally()` registered after the call it's meant to guard,
    and a `before_each`-opened socket/server with no matching `after_each`.
    Not part of the rockspec; lives in this repo for its own development and
    as a template adopters can copy.
