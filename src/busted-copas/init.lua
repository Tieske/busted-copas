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
--   bc.wait(function() return result ~= nil end, 3)
--   assert.equals("expected", result)
function M.wait(condition, timeout, interval)
  timeout  = timeout  or 5
  interval = interval or 0.05
  local deadline = copas.gettime() + timeout
  while not condition() do
    local remaining = deadline - copas.gettime()
    if remaining <= 0 then
      error(("Timeout: condition not met within %.2f seconds"):format(timeout), 2)
    end
    copas.pause(math.min(interval, remaining))
  end
end



--- Wrap `fn` so it fails if it doesn't complete within `seconds`.
-- Runs `fn` as its own Copas future. If `seconds` elapses first, the future
-- is cancelled (it stops being scheduled — Lua coroutines can't be forcibly
-- terminated, so this is abandonment, not interruption) and the wrapped
-- function raises an error.
--
-- Returns a *function*, meant to be handed to busted's own `it()` as the
-- test body — `bc.timeout` never calls `it` itself (see ADR 0004).
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
-- @tparam function fn       the test body; called with no arguments, since
--                           busted's own `it()` never passes any either
-- @tparam[opt] string msg  error message to use on timeout, replacing the
--                          default "Test timed out after %.2f seconds"
-- @usage
--   it("completes the handshake in time", bc.timeout(5, function()
--     local skt = assert(socket.connect(host, port))
--     finally(function() copas.close(skt) end)
--     local data = copas.receive(skt)
--     assert.equals("hello", data)
--   end))
function M.timeout(seconds, fn, msg)
  msg = msg or ("Test timed out after %.2f seconds"):format(seconds)

  return function()
    local fut = future.addthread(fn)

    local timed_out = false
    local t = timer.new({
      delay = seconds,
      recurring = false,
      callback = function()
        timed_out = fut:cancel()
      end,
    })

    local ok, err = fut:get()
    t:cancel()

    if not ok then
      if timed_out then
        error(msg, 2)
      end
      error(err, 2)
    end
  end
end



return M
