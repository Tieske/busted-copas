# busted-copas

Lets Copas-based async Lua code be tested with the Busted test framework, by
inverting which side owns the run loop: Copas runs the loop, Busted's own
runner executes inside it as a coroutine.

## Language

**The interpreter wrapper**:
The script (`bin/busted-copas.lua`) that Busted invokes in place of a plain
Lua interpreter; it runs Busted's own entry script inside a Copas coroutine
and owns the `copas.loop()` call.
_Avoid_: the runner — Busted has its own, unrelated internal runner
(`busted/runner.lua`); using "runner" for ours invites confusion with that.

**The helper module**:
The `require "busted-copas"` module (`src/busted-copas/init.lua`) providing
opt-in async test utilities (`pause`, `wait`, `timeout`). Not required to
use the interpreter wrapper — every test can already use Copas-native calls
without it.
_Avoid_: busted-copas on its own — ambiguous, since that name also refers to
the project/rock as a whole and to the interpreter wrapper's installed
command name. Qualify as "the helper module" when the distinction matters.

**Test timeout**:
A whole-test safety net (`cb.timeout(seconds, fn)`) that abandons the test's
coroutine if it hasn't finished within `seconds`. The fallback for hangs an
operation timeout wouldn't catch (e.g. a chain of short waits that
individually never expire).
_Avoid_: timeout (bare), cit — always qualify as "test timeout" vs.
"operation timeout" to keep the two mechanisms distinct.

**Operation timeout**:
A timeout scoped to a single Copas call: `copas.settimeout` before socket
I/O, or the inline `timeout` argument to `lock:get`/`semaphore:take`. The
preferred, more precise mechanism — reach for a test timeout only for what
this can't catch.
_Avoid_: timeout (bare)

**Abandonment**:
What happens to a cancelled future's coroutine: the scheduler permanently
stops resuming it. Not termination — Lua coroutines can't be interrupted
mid-yield, so any code after the suspended point never runs, including
inline cleanup that isn't registered via `finally()` beforehand.
_Avoid_: cancellation (that's the action taken — `future:cancel()`;
abandonment is the coroutine's resulting state), killing, termination.

**Run teardown**:
The one-time `copas.cancelall()` call in the interpreter wrapper, made after
Busted's entire suite finishes — force-closes every socket/server and
cancels every thread so `copas.loop()` can exit even if a test leaked
state. Distinct from per-test cleanup, which happens continuously via
`finally()` throughout the run, not once at the end.
_Avoid_: cleanup (bare) — reserve for test-scoped cleanup.
