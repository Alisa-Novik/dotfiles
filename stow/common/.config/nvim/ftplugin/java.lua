local mason_jdtls = vim.fn.stdpath("data") .. "/mason/packages/jdtls/bin/jdtls"
local jdtls_cmd = vim.fn.executable("jdtls") == 1 and "jdtls" or mason_jdtls

local config = {
	cmd = { jdtls_cmd },
	root_dir = vim.fs.dirname(vim.fs.find({ "gradlew", ".git", "mvnw" }, { upward = true })[1]),
}
require("jdtls").start_or_attach(config)
