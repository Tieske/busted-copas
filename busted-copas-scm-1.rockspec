local package_name = "busted-copas"
local package_version = "scm"
local rockspec_revision = "1"
local github_account_name = "Tieske"
local github_repo_name = "busted-copas"


package = package_name
version = package_version.."-"..rockspec_revision

source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
  branch = (package_version == "scm") and "main" or nil,
  tag = (package_version ~= "scm") and package_version or nil,
}

description = {
  summary = "Test framework for testing async Copas applications, on top of Busted",
  detailed = [[
    Test framework for testing async Copas applications, on top of Busted
  ]],
  license = "MIT",
  homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
}

dependencies = {
  "lua >= 5.1, < 5.6",
}

build = {
  type = "builtin",

  modules = {
    ["busted-copas.init"] = "src/busted-copas/init.lua",
  },

  install = {
    bin = {
      ["busted-copas"] = "bin/busted-copas.lua",
    }
  },

  copy_directories = {
    -- can be accessed by `luarocks busted-copas doc` from the commandline
    "docs",
  },
}
