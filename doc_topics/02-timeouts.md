# Timeouts

## Two kinds of timeout

**Operation timeout** — scoped to a single Copas call, and the preferred,
most precise mechanism. Reach for a test timeout only for what this can't
catch:

```lua
copas.settimeout(skt, seconds)
local data, err = copas.receive(skt) -- returns nil, "timeout" on expiry
```

Locks and semaphores take an inline `timeout` argument directly instead:

```lua
lock:get(timeout)
semaphore:take(n, timeout)
```

**Test timeout** — a whole-test safety net, `bc.timeout(seconds, fn)`, for
catching gross hangs that per-operation timeouts wouldn't — for example a
chain of many short waits that individually never expire but collectively
hang.

A test timeout means the test's coroutine is **abandoned**, not terminated:
Lua coroutines can't be forcibly interrupted mid-yield, so no code after the
point it was suspended ever runs, including any inline cleanup that isn't
behind a `finally()` registered beforehand. See "Limitations" below.

## Helper API

`require "busted-copas"` gives you three functions. None of them are Busted
DSL keywords — they're plain functions, callable from anywhere inside a spec
file.

**`bc.pause(seconds)`** — a plain re-export of `copas.pause`, so tests only
need to `require` one module.

**`bc.wait(condition, timeout, interval)`** — polls `condition()` every
`interval` seconds (default `0.05`) until it returns truthy, raising an
error if `timeout` seconds (default `5`) elapse first:

```lua
local result
start_async_operation(function(r) result = r end)
bc.wait(function() return result ~= nil end, 3)
assert.equals("expected", result)
```

**`bc.timeout(seconds, fn, msg)`** — wraps `fn` so it fails if it doesn't
complete within `seconds`, abandoning it otherwise. `bc.timeout` returns a
*function*, meant to be handed to Busted's own `it()` as the test body —
it never calls `it` itself:

```lua
it("completes the handshake in time", bc.timeout(5, function()
  local skt = assert(socket.connect(host, port))
  finally(function() copas.close(skt) end)
  local data = copas.receive(skt)
  assert.equals("hello", data)
end))
```

Composes directly with Busted's own `assert.has_error` for "fails within N
seconds" assertions — no dedicated helper needed:

```lua
assert.has_error(bc.timeout(1, function()
  -- ... something that should error ...
end))
```

### The `finally()`-ordering requirement

Any resource `fn` acquires must be registered for cleanup via `finally()`
**immediately**, before the operation that might be the one that times out.
`finally()` runs in Busted's own still-alive coroutine regardless of whether
`fn`'s coroutine ever resumes again, so registering early is what makes
cleanup survive a timeout — the same acquire-then-immediately-register
discipline a plain Busted test already needs (skip it, and an exception
between acquisition and registration leaks the resource today, timeout or
not).

### Subtasks manage their own errors

A background thread a test spawns with a bare `copas.addthread` (not wrapped
in a `copas.future`) that errors independently goes to Copas's default error
handler — it prints and vanishes, without failing the test. If a subtask's
outcome matters to a test's correctness, the test should observe it
explicitly: wrap it in its own `copas.future` and check the result, the same
way `bc.timeout` observes its own future.

## Limitations

- **Coroutine abandonment**: a `bc.timeout` expiry stops the test's
  coroutine from ever being resumed again. It does not run any code after
  the point it was suspended, including inline cleanup that isn't behind a
  `finally()` registered earlier. This is fundamental to how Lua coroutines
  work, not specific to this library, but it's the single most important
  thing to understand correctly.
- **Stray background-thread errors aren't forwarded**: see "Subtasks manage
  their own errors" above.
- **Busted's re-exec arg quoting**: on every currently released Busted
  version, arguments passed through the `lua`-interpreter re-exec are joined
  unescaped — a spec path containing a space or shell metacharacter can
  break the re-exec. This is a Busted-side issue, not something fixable
  from this library.

See the [echo server example](../examples/echo_server_spec.lua.html) for
`bc.timeout` and `finally()` used together against real socket I/O.
