unused_args     = false
redefined       = false
max_line_length = 100

globals = {
--    "ngx",
}

not_globals = {
    -- deprecated Lua 5.0 functions
    "string.len",
    "table.getn",
}

include_files = {
  "**/*.lua",
  "**/*.rockspec",
  ".busted",
  ".luacheckrc",
}

files["spec/**/*.lua"] = {
    std = "+busted",
}

files["examples/**/*.lua"] = {
    std = "+busted",
}

exclude_files = {
    -- The Github Actions Lua Environment
    ".lua",
    ".luarocks",
    ".install",

    -- Illustrative bad-pattern fixtures for the check-async-test-hygiene
    -- skill; read by that skill, never run as part of the suite. Matched
    -- without a fixed prefix since luacheck reaches the directory via its
    -- `.claude/skills/` symlink, not only its real `.agents/skills/` path.
    "**/check-async-test-hygiene/fixtures/**/*.lua",
}

