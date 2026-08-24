# Pin copas/busted to latest, not the lowest version that happens to work

Most libraries float their dependency floors as low as compatibility
allows, to minimize friction for adopters on older toolchains. Decided
against that here: the rockspec pins `copas >= 4.12.0` and `busted >=
2.3.0` — the current latest releases at the time of writing — rather than
the lowest versions the code could be made to run on.

This is a deliberate policy choice, not just a default: the library was
built directly against APIs with real version constraints (`copas.gettime`
wasn't a public field until 4.8.0; `copas.future` and `copas.removethread`,
core to the test-timeout design in ADR 0002, are recent), and there was an
explicit decision not to carry old-version compatibility shims for their
own sake. A future contributor lowering these floors to "widen support"
should know it was a deliberate choice, not an oversight, and would need to
re-verify every version-sensitive API this library depends on.

Note this is independent of the Lua *interpreter* compatibility matrix
(5.1–5.5, LuaJIT), which stays wide — confirmed both dependencies still
support that full range even at their latest versions.
