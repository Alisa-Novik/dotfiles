local config = {
	cmd = { "/home/alice/.local/share/nvim/mason/packages/jdtls/bin/jdtls" },
	root_dir = vim.fs.dirname(vim.fs.find({ "gradlew", ".git", "mvnw" }, { upward = true })[1]),
}
require("jdtls").start_or_attach(config)
