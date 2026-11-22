local bc     = require "busted-copas"
local copas  = require "copas"



describe("busted-copas.wait()", function()

  it("returns when condition becomes true", function()
    local flag = false
    copas.addthread(function()
      copas.pause(0.05)
      flag = true
    end)
    bc.wait(function() return flag end, 2)
    assert.is_true(flag)
  end)


  it("raises an error on timeout", function()
    assert.has_error(function()
      bc.wait(function() return false end, 0.1, 0.02)
    end)
  end)

end)



describe("busted-copas.timeout()", function()

  local cleaned_up

  setup(function()
    cleaned_up = false
  end)



  it("passes when fn completes in time", bc.timeout(2, function()
    copas.pause(0.05)
  end))


  it("raises an error when fn takes too long", function()
    assert.has_error(bc.timeout(0.1, function()
      copas.pause(1)
    end))
  end)


  it("propagates fn's own error, raised immediately", function()
    assert.error_matches(bc.timeout(2, function()
      error("boom")
    end), "boom")
  end)


  it("propagates fn's own error, raised after a yield", function()
    assert.error_matches(bc.timeout(2, function()
      copas.pause(0.05)
      error("boom")
    end), "boom")
  end)


  -- finally() only runs as part of busted's own teardown for the test that
  -- registered it, once that test's `it()` body returns — not synchronously
  -- while it's still running. So observing it needs two tests: this one
  -- triggers the timeout and sets `cleaned_up` in its finally(); the next
  -- one asserts it, relying on busted having already run that teardown by
  -- the time it starts. This is a deliberate dependency between the two,
  -- not an accident — there's no way to observe post-abandonment cleanup
  -- synchronously from within the test that triggered it.
  it("registers finally() before the call that ends up timing out", function()
    assert.has_error(bc.timeout(0.1, function()
      finally(function() cleaned_up = true end)
      copas.pause(1) -- this is what times out
    end))
  end)


  it("still ran that finally(), despite the timeout abandoning its test", function()
    assert.is_true(cleaned_up)
  end)

end)



describe("busted-copas.pause()", function()

  it("is an alias for copas.pause", function()
    assert.equals(copas.pause, bc.pause)
  end)

end)
