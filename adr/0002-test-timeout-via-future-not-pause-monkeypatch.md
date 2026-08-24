---
status: accepted
---

# Test timeout built on copas.future + timer, not a copas.pause monkey-patch

The original design for a whole-test timeout shadowed the global
`copas.pause` for the duration of the test, on the theory that every
cooperative yield passes through it. Verified against Copas source that this
is false: `copas.receive`/`copas.send` wait for socket readiness via a
`coroutine.yield()` call captured as a local upvalue at module load time,
invisible to any reassignment of `copas.pause` — the primary yield point for
the exact I/O-bound tests this feature exists for would silently never time
out.

Decided to build the test timeout on `copas.future` (run the test body as
its own future) plus a `copas.timer` that calls `future:cancel()` on expiry
— both real, public API (`future:cancel()` is itself built on the public
`copas.removethread`), not internals. `future:get()`'s built-in `pcall`
around the task body means the test's own errors already propagate
correctly with no extra plumbing.

## Considered options

- **`copas.pause` monkey-patch** (original design): rejected, doesn't
  actually intercept the yields it needs to.
- **`copas.addtask`**: doesn't exist in Copas; a dead end investigated and
  ruled out.
- **Copas's own core timeout (`copas.timeout`-style, kills the whole
  scheduler)**: rejected — it would stop every test, not just the one that
  hung.

## Consequences

Cancelling a future is abandonment, not termination (see `CONTEXT.md`) — the
timed-out coroutine's own inline cleanup code never runs. Cleanup for
anything a test timeout might interrupt must go through `finally()`,
registered immediately after resource acquisition and before the call that
might be the one that hangs, so it survives even though the test's coroutine
itself never resumes again. Verified against Busted source that `finally()`
runs in Busted's own live coroutine, independent of the abandoned one.
