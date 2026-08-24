# Test timeout is a plain require-based wrapper, not a Busted DSL keyword

Considered giving the test timeout first-class call syntax — a `cit(...)`
function usable directly in spec files like `it`/`describe`, either via
Busted's real plugin API (`busted.register`, the same mechanism `it` itself
is built on) or by injecting a plain global from the interpreter wrapper.

Both were rejected. `busted.register` means depending on Busted's internal
executor plumbing (`block.lazySetup`, `busted.safe`, `busted.status`) —
undocumented internals, not a stable contract, for a cosmetic gain. The
global-injection route has a real correctness bug, not just an ergonomic
downside: Busted sandboxes each spec file's environment via `setfenv`, and
nested closures inside a wrapped file inherit that sandboxed `_ENV` — but a
function defined outside that sandbox (in the interpreter wrapper, or in any
`require`d module) permanently carries the plain `_ENV` it was compiled
with, regardless of when it's assigned to a global. A `cit`/`timeout`
function defined that way could never resolve a bareword `it` call inside
its own body; `it` is confirmed never written to real `_G` anywhere in
Busted's source, only into its own per-context env table.

Decided the test timeout is a plain function, `cb.timeout(seconds, fn)`,
that returns a wrapped callback for the spec file's own `it(...)` call to
use — `it("desc", cb.timeout(5, function() ... end))`. It never itself
calls `it`, sidestepping the environment problem entirely rather than
working around it, at the cost of needing `require "busted-copas"` and one
extra pair of parens per call site instead of a bare `cit(...)`.
