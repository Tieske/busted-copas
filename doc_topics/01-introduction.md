# Introduction

`busted-copas` lets you test asynchronous [Copas](https://github.com/lunarmodules/copas)
code with the [Busted](https://github.com/lunarmodules/busted) test framework,
with no special test syntax and no `done()` callbacks.

## Installation

    luarocks install busted-copas

## Setup

Add a single line to your project's `.busted` file:

```lua
-- .busted
return {
  default = {
    lua = "busted-copas",
    -- ...your other settings stay as they were
  },
}
```

From here on, run your tests exactly as before:

    busted

No other change is needed. `busted-copas` is a drop-in `lua` interpreter value
for Busted's own config — it is not a CLI you invoke yourself.

## Why it works

Normally Busted owns the outermost execution loop. Here, that's inverted:
Copas owns the loop, and Busted's own runner executes *inside* it, as a
single Copas coroutine thread. Any test that calls a Copas-native API —
socket I/O, `copas.pause`, timers, locks, semaphores — simply yields and
resumes the way it would in any other Copas coroutine. This holds for
**every** test in the suite, not just ones that opt into the helper module
(see the next topic) — the `.busted` change above is sufficient on its own
to make async Copas code testable.

## Compatibility

- Lua 5.2 – 5.5
- Copas >= 4.12.0
- Busted >= 2.3.0

Lua 5.1 and LuaJIT are not supported: Busted wraps every `it()` body in
`xpcall` for per-test error isolation, and Lua 5.1-class VMs cannot yield a
coroutine across that boundary — a test calling a yielding Copas primitive
(`copas.pause`, `copas.receive`, etc.) directly would raise *"attempt to
yield across C-call boundary"* every time. Lua 5.2 introduced yieldable
`pcall`/`xpcall`, which is what makes this library's core premise hold.
