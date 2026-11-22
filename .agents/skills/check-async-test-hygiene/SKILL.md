---
name: check-async-test-hygiene
description: Check a Busted spec for async Copas test-hygiene bugs — a finally() registered after the call it's meant to guard, or a before_each-opened socket/server with no matching after_each. Use when writing, editing, or reviewing a Busted spec that tests async Copas code, or when asked to check async test hygiene.
---

# Check async test hygiene

A dev-time review for two hygiene bugs this project's helper module
(`busted-copas`) and `doc_topics/02-timeouts.md` establish conventions
for. Neither is a `luacheck` violation — both are structural, about
*order* and *pairing*, not syntax — so this is a reading review, not a
lint pass.

`fixtures/` holds two deliberately-bad spec files exercising each check,
for validating this skill itself; they're excluded from `luacheck` (see
`.luacheckrc`) and never run as part of the real suite.

## Process

1. **Pick the targets.** Use the file path(s) given as an argument. With
   none, scan every `spec/**/*.lua` and `examples/**/*.lua`, excluding
   `spec/fixtures/` (that directory holds fixtures for this project's own
   runner tests, which poke at busted internals directly — not real
   specs; see `spec/01-runner_spec.lua`).
2. **Read each target in full.**
3. **Apply both checks below** to every `it()` / `before_each` /
   `after_each` body in the file.
4. **Report findings** as a short list per file: which check failed, the
   line, the offending snippet, and the one-line fix. If a file has no
   findings under either check, say so explicitly — don't stay silent on
   a clean file.

## Check 1: late `finally()`

Any resource a test acquires (a socket via `socket.tcp()` / `socket.bind()`,
a lock, a semaphore slot) must have its `finally()` cleanup registered
**immediately after acquisition** — before the next statement, especially
one that can yield or fail (a connect, a send/receive, anything
`copas.*`). `finally()` runs in Busted's own still-alive coroutine
regardless of whether the acquiring coroutine ever resumes again, so an
operation that times out or errors between acquisition and registration
leaks the resource — see "The `finally()`-ordering requirement" in
`doc_topics/02-timeouts.md`.

**Good** (`examples/echo_server_spec.lua`):

```lua
local client = copas.wrap(assert(socket.tcp()))
finally(function() copas.close(client) end)
assert(client:connect("127.0.0.1", PORT)) -- could fail/time out; cleanup is already registered
```

**Bad** — flag this:

```lua
local client = copas.wrap(assert(socket.tcp()))
assert(client:connect("127.0.0.1", PORT)) -- if this times out, finally() below never runs
finally(function() copas.close(client) end)
```

The test: walk forward from the acquiring statement — is the very next
statement the matching `finally()` call? If anything else sits between
them, flag it, regardless of whether that statement happens to succeed in
practice; the bug is latent until it doesn't.

## Check 2: `before_each` cleanup without a matching `after_each`

A `before_each` that opens a socket or server (`socket.bind`,
`socket.tcp()`, `copas.addserver`) and assigns it to a `describe`-level
variable must have a matching `after_each` in the *same* `describe` that
closes or removes it (`copas.close`, `copas.removeserver`, `:close()`).
Without it, every test in that `describe` leaks a server/socket; relying
on the interpreter wrapper's run teardown (`copas.cancelall()`) only
catches the suite's *final* leak, not per-test isolation.

**Good** (`examples/echo_server_spec.lua`):

```lua
before_each(function()
  server = assert(socket.bind("127.0.0.1", PORT))
  copas.addserver(server, function(skt) ... end)
end)

after_each(function()
  copas.removeserver(server)
end)
```

**Bad** — flag this:

```lua
before_each(function()
  server = assert(socket.bind("127.0.0.1", PORT))
  copas.addserver(server, function(skt) ... end)
end)
-- no matching after_each anywhere in this describe
```

The test: for every `before_each` that opens a socket/server, confirm the
enclosing `describe` also has an `after_each` that closes/removes that
same variable. A `before_each` that opens nothing network-related doesn't
trigger this check.
