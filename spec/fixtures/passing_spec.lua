local copas = require "copas"

describe("fixture: passing", function()

  it("pauses briefly and passes", function()
    copas.pause(0.01)
    assert.is_true(true)
  end)

end)
