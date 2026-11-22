-- These are synchronous tests (no copas needed); they shell out to the CLI.

local function run_busted(args)
  -- Shell out to busted, which uses bin/busted-copas via .busted config.
  -- Returns exit code and stdout.
  local cmd = "busted " .. args .. " 2>&1; echo EXIT:$?"
  local out = io.popen(cmd):read("*a")
  local code = tonumber(out:match("EXIT:(%d+)"))
  return code, out
end


local function assert_exit_code(expected, code, out)
  -- surface the subprocess's own output on a mismatch; a bare exit-code
  -- diff gives no clue which assertion/error inside it actually fired.
  if code ~= expected then
    io.stderr:write(out)
  end
  assert.equals(expected, code)
end



describe("busted-copas runner", function()

  it("exits 0 when all tests pass", function()
    local code, out = run_busted("spec/fixtures/passing_spec.lua")
    assert_exit_code(0, code, out)
  end)


  it("exits 1 when a test fails", function()
    local code, out = run_busted("spec/fixtures/failing_spec.lua")
    assert_exit_code(1, code, out)
  end)


  it("supports standard busted flags (e.g. --pattern)", function()
    local code, out = run_busted("--pattern=passing spec/fixtures/")
    assert_exit_code(0, code, out)
  end)


  it("exits cleanly even if a spec leaks a copas server", function()
    -- regression test for the copas.cancelall() call in bin/busted-copas;
    -- without it this invocation would hang instead of exiting.
    local code, out = run_busted("spec/fixtures/leaky_server_spec.lua")
    assert_exit_code(0, code, out)
  end)

end)
