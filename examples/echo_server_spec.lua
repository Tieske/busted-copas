-- example to add to documentation
-- Run with: busted examples/echo_server_spec.lua

local copas  = require "copas"
local socket = require "socket"
local bc     = require "busted-copas"

local PORT = 19876

describe("echo server", function()
  local server


  before_each(function()
    -- Start a trivial TCP echo server as a Copas thread.
    server = assert(socket.bind("127.0.0.1", PORT))
    copas.addserver(server, function(skt)
      skt = copas.wrap(skt)
      local line = skt:receive("*l")
      skt:send(line .. "\n")
    end)
  end)


  after_each(function()
    copas.removeserver(server)
  end)


  it("echoes a line back to the client", bc.timeout(5, function()
    local client = copas.wrap(assert(socket.tcp()))
    finally(function() copas.close(client) end)
    assert(client:connect("127.0.0.1", PORT))

    client:send("hello\n")
    local received = client:receive("*l")

    assert.equals("hello", received)
  end))

end)
