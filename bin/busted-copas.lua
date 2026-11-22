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
