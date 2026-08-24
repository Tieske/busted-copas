# No implicit safety nets for stray thread errors or leaked test state

Two related gaps were identified and deliberately left unaddressed by the
library itself, rather than patched with automatic detection:

1. An error inside a `copas.addthread` a test spawns that isn't wrapped in
   its own `copas.future` goes to Copas's default error handler (prints,
   doesn't fail anything) — a test can pass green while a background thread
   silently errored.
2. A leaked thread or unclosed socket from one test can affect a later test
   in the same run; `copas.cancelall()` (ADR 0001) only fires once, after
   the *entire* suite finishes, not between individual tests.

Considered installing a global `copas.seterrorhandler` default handler to
catch (1) and surface it via `after_each`. Rejected: if a spawned subtask's
outcome matters to a test's correctness, the test should observe it
explicitly — e.g. wrap it in its own `future` and check the result, the same
way the test timeout (ADR 0002) observes its own future. A library-level
safety net would just be catching what should have been synchronized on in
the first place; assertions belong on the thread executing the `it` block.

For (2), no runtime auto-reset/registry-diffing safety net was built either.
Both gaps are addressed the same way instead: a companion write-time
checking tool (planned; see `tasks/initial-plan.md` §Implementation Order)
that reviews spec files for missing `finally()` registration and unclosed
`before_each` resources, catching the mistake before it ships rather than
papering over it at runtime.
