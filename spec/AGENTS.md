# Guidance for AI agents — test suite

This file covers conventions for the Busted test files in `./spec/`.

## Test framework

Tests use [Busted](https://lunarmodules.github.io/busted/). Run them with `busted` from the repository root. Lint with `luacheck`.
Coverage information will be in the file `luacov.report.out`.

When running tests, ALWAYS specify `--output=utfTerminal` — it produces far less output than the default `gtest` handler, saving tokens.

Run `make dev` once, to install the test tooling. After that, AI agents should run `busted`/`luacheck` directly rather than through `make test`/`make lint` — the Makefile wraps them in extra output meant for humans, not agents.

## File layout

Spec files are named with a numeric prefix and a descriptive suffix: `NN-topic_spec.lua`. The numbering controls execution order and groups related concerns.

When adding tests, place them in the file that matches their scope. Only create a new file when the topic is clearly distinct from existing files.

## MECE test cases

Test cases within a `describe` block should be MECE: mutually exclusive, collectively exhaustive.

- **Mutually exclusive**: each test exercises a distinct branch, for a distinct reason. If a new test would only restate an existing one under a different description, it's not a new case — cut the weaker of the two.
- **Collectively exhaustive**: enumerate the branches the code under test actually has — each input case, each error path, each boundary — and confirm each one has a test. A gap here is a missing test, not a missing assertion inside an existing one. When full coverage is genuinely impractical (the case count explodes combinatorially, or a branch can't be exercised in isolation), don't skip it silently: check with the user first, and if they agree to leave it untested, document the reason — a comment at the branch, or a note in the spec file — the same way any other genuinely-not-applicable test is documented.

## Test isolation

In Busted the test files are run as Lua files; all `describe` blocks execute at load time. All other blocks only run at test-runtime. Therefore:

- All initialization MUST be in `setup` or `before_each` blocks, NEVER directly in `describe` blocks.
- Variables may be declared at the `describe` level (to keep them in scope), but MUST NOT be assigned values there.
- The only exception is code that generates tests (table-driven tests), which is designed to run at the `describe` level.

Example:

```lua
describe("some block", function()

  local my_module    -- only declare here, no values!

  before_each(function()
    _G._TEST = true -- set a global test flag
    my_module = require "my.module.something"   -- initialize here
  end)


  after_each(function()
    _G._TEST = nil
  end)



  it("a test", function()
    -- test goes here
  end)


  it("another test", function()
    -- test goes here
  end)

end)
```

## Exporting internals for testing

Modules can export elements if the global _G._TEST flag is set. This makes it easier to
test private functions, or validate internal state during testing.

```lua
local tracking_table = {}

local M = {
  do_something = function(self, ...)
     -- implementation goes here
  end,
}

if _G._TEST then
  -- change name such that code using `M.tracking_table` instead of plain `tracking_table`
  -- doesn't accidentally work in test, but fails in prod. Prefix with "_".
  M._tracking_table = tracking_table
end

return M
```

## Code style

Style follows [.editorconfig](../.editorconfig) (LF line endings) and [.luacheckrc](../.luacheckrc).

### General

- Keep test descriptions concise and starting with a verb (e.g. "creates ...", "rejects ...", "transitions ...").

### Vertical whitespace

- 3 blank lines between `describe` blocks
- 1 blank line at the start of a `describe` block
- 2 blank lines between other blocks (`it`, `setup`, `before_each`, etc)
- 3 blank lines between initialization (`setup`/`teardown`/etc) and the first `it` or `describe` block
- 1 blank line between multiple closing `end)` statements

### Test file structure

When unit testing functions or methods, each function should have its own `describe` block inside the module-level `describe`. This keeps tests grouped by function and provides a clear structure.

Example:

```lua
describe("my_object", function()

  describe("some_method()", function()

    it("prints something cool", function()
      -- implementation here
    end)

  end)



  describe("another_method()", function()

    it("throws an error on something bad", function()
      -- implementation here
    end)

  end)

end)
```
