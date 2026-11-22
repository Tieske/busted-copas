#!/usr/bin/env lua
--- A Lua interpreter wrapper that runs busted inside a Copas coroutine loop.
--
-- Referenced via the `lua` key in an adopting project's .busted file, in
-- place of a plain Lua interpreter:
--
--   return { default = { lua = "busted-copas", ... } }
--
-- Busted then invokes this script as:
--
--   busted-copas <busted-main-script> [args...]
--
-- `arg[1]` is busted's main script; it gets shifted to `arg[0]` so busted's
-- own arg-parsing sees the expected layout, then `dofile()`-ed inside
-- `copas.addthread()`, before `copas.loop()` starts.
-- @script busted-copas
-- @usage
-- -- in the adopting project's .busted file:
-- return { default = { lua = "busted-copas" } }



local copas = require "copas"



local busted_script = table.remove(arg, 1)  -- was arg[1]
-- busted expects arg[0] = itself; mutating the global `arg` table is required here.
arg[0] = busted_script -- luacheck: ignore 122



-- On Lua 5.1/5.2 (LuaJIT included: it reports _VERSION as "Lua 5.1"), busted
-- signals a non-zero exit by raising a bare, message-less error() instead of
-- calling os.exit() (see busted/compatibility.lua's `exit`). Run as a plain
-- top-level script, that reaches the Lua interpreter's own uncaught-error
-- handling, which exits the process non-zero on busted's behalf — but inside
-- a Copas coroutine it would otherwise just be swallowed by Copas's default
-- per-thread error handler (prints a traceback, moves on), silently
-- reporting success regardless of test results. This handler tells that
-- deliberate, message-less signal (err == nil) apart from a genuine error,
-- which always has a message.
local function dofile_error_handler(err)
  if err == nil then
    return nil
  end
  return debug.traceback(err, 2)
end

copas.addthread(function()
  -- busted_script is captured as an upvalue, not passed as an xpcall
  -- argument: Lua 5.1's xpcall doesn't forward extra arguments to the
  -- protected function (only Lua 5.2+ does) — passing it as an argument
  -- would silently call dofile() with none, which reads from stdin instead.
  local ok, err = xpcall(function() return dofile(busted_script) end, dofile_error_handler)

  -- copas.loop() only returns once ALL scheduler activity clears: every
  -- addthread AND every addserver-registered listener. A single spec that
  -- opens a server and forgets to close it would otherwise hang the process
  -- forever instead of failing with a message. cancelall() is copas's own
  -- test-teardown primitive: it force-closes every socket, removes every
  -- server, and cancels every thread, then lets the loop exit cleanly.
  -- It must be called from inside the running loop, which this is.
  copas.cancelall()

  if not ok then
    -- restore the exit code busted intended but couldn't deliver itself;
    -- a genuine (non-signal) error still gets its traceback printed first.
    if err then
      io.stderr:write(err, "\n")
    end
    os.exit(1, true)
  end
end)



copas.loop()
