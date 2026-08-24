#!/usr/bin/env lua

--- CLI application.
-- Description goes here.
-- @script busted-copas
-- @usage
-- # start the application from a shell
-- busted-copas --some --options=here

print("Welcome to the busted-copas CLI, echoing arguments:")
for i, val in ipairs(arg) do
  print(i .. ":", val)
end
