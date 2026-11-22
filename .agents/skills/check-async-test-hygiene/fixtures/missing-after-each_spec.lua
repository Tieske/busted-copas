-- BAD FIXTURE for the check-async-test-hygiene skill — see its SKILL.md.

local copas  = require "copas"
local socket = require "socket"

local PORT = 19879

describe("bad fixture: missing after_each cleanup", function()

  local server

  before_each(function()
    server = assert(socket.bind("127.0.0.1", PORT))
    copas.addserver(server, function() end)
  end)

  -- no after_each here — the server opened above is never closed

  it("never cleans up the server opened in before_each", function()
    assert.is_not_nil(server)
  end)

end)
