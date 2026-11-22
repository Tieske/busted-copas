# Drop Lua 5.1 and LuaJIT support; raise the floor to Lua 5.2

Busted wraps every `it()`/`describe()`/etc. body in `xpcall()` for per-test
error isolation (`busted.safe()` in `busted/core.lua`). A test that calls a
yielding Copas primitive directly inside that body — `copas.pause`,
`copas.receive`, anything that does `coroutine.yield()` — has to yield across
that `xpcall` frame to reach Copas's own scheduler resume call.

Lua 5.1-class VMs cannot do this: yielding across a `pcall`/`xpcall` boundary
was only added in Lua 5.2 ("yieldable pcall"). Confirmed empirically against
both LuaJIT (2.1, via Homebrew) and a from-source PUC Lua 5.1.5 build: the
exact same fixture (a plain `it()` calling `copas.pause(0.01)`) raises
*"attempt to yield across C-call boundary"* (LuaJIT's wording) or *"...across
metamethod/C-call boundary"* (PUC 5.1's wording) on both, while the identical
fixture passes cleanly on Lua 5.2 through 5.5.

This isn't a LuaJIT-specific quirk, or something fixable from this library's
side — it's a Lua 5.1 VM-era limitation that busted's own architecture runs
straight into, and it directly contradicts this library's core premise (CONTEXT.md:
"any test that calls a Copas-native API... simply yields and resumes
naturally"). A library whose main selling point silently doesn't hold on part
of its declared compatibility matrix is worse than one that's honest about a
narrower matrix.

Decided to drop Lua 5.1 and LuaJIT entirely rather than document the
limitation and keep them: raised the rockspec's `lua` dependency floor to
`>= 5.2, < 5.6` (which also excludes LuaJIT, since it satisfies `lua 5.1` for
dependency-resolution purposes) and removed `5.1`/`luajit`/`luajit-openresty`
from the CI matrix. The alternative — keep them listed as "supported" with a
documented caveat that the one thing this library exists for doesn't work
there — was rejected as misleading to adopters.

This was discovered mid-investigation of an unrelated bug: a wrapper-side
`xpcall` argument-forwarding bug (Lua 5.1's `xpcall` doesn't forward extra
arguments to the protected function, only 5.2+ does) was silently causing
busted's whole test run to no-op on Lua 5.1 specifically, which is what first
surfaced the yield-boundary problem once that no-op was fixed. The
argument-forwarding bug is fixed in `bin/busted-copas.lua` regardless of this
ADR, since it would otherwise also affect any future Lua 5.1-class target.
