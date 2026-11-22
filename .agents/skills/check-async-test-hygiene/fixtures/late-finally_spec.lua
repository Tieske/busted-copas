-- BAD FIXTURE for the check-async-test-hygiene skill — see its SKILL.md.

local copas  = require "copas"
local socket = require "socket"
local bc     = require "busted-copas"

local PORT = 19878

describe("bad fixture: late finally()", function()

  it("registers finally() after the call that could time out", bc.timeout(5, function()
    local client = copas.wrap(assert(socket.tcp()))
    assert(client:connect("127.0.0.1", PORT)) -- if this times out, finally() below never runs
    finally(function() copas.close(client) end) -- too late
  end))

end)
