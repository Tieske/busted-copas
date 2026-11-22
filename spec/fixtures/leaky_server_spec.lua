local copas  = require "copas"
local socket = require "socket"

describe("fixture: leaky server", function()

  it("opens a server and never closes it", function()
    local server = assert(socket.bind("127.0.0.1", 0))
    copas.addserver(server, function() end)
    -- deliberately no cleanup — this is what cancelall() must recover from
  end)

end)
