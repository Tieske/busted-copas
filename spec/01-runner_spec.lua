-- These are synchronous tests (no copas needed); they shell out to the CLI.

local function run_busted(args)
  -- Shell out to busted, which uses bin/busted-copas via .busted config.
  -- Returns exit code and stdout.
  local cmd = "busted " .. args .. " 2>&1; echo EXIT:$?"
  local out = io.popen(cmd):read("*a")
  local code = tonumber(out:match("EXIT:(%d+)"))
  return code, out
end



describe("busted-copas runner", function()

  it("exits 0 when all tests pass", function()
    local code = run_busted("spec/fixtures/passing_spec.lua")
    assert.equals(0, code)
  end)


  it("exits 1 when a test fails", function()
    local code = run_busted("spec/fixtures/failing_spec.lua")
    assert.equals(1, code)
  end)


  it("supports standard busted flags (e.g. --pattern)", function()
    local code = run_busted("--pattern=passing spec/fixtures/")
    assert.equals(0, code)
  end)


  it("exits cleanly even if a spec leaks a copas server", function()
    -- regression test for the copas.cancelall() call in bin/busted-copas;
    -- without it this invocation would hang instead of exiting.
    local code = run_busted("spec/fixtures/leaky_server_spec.lua")
    assert.equals(0, code)
  end)

end)
