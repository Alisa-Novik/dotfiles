-- Local additions on top of craftzdog's config
vim.pack.add({
	{ src = "https://github.com/preservim/vim-pencil" },
})

vim.g["pencil#wrapModeDefault"] = "soft"
vim.g["pencil#conceallevel"] = 2

local group = vim.api.nvim_create_augroup("local-pencil", { clear = true })
local soft = { "markdown", "mkd", "text", "tex", "plaintex", "rst", "asciidoc" }
local hard = {
	gitcommit = { wrap = "hard", textwidth = 72 },
	mail = { wrap = "hard", textwidth = 60 },
}

local function enable(buf, opts)
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		vim.api.nvim_buf_call(buf, function()
			vim.fn["pencil#init"](opts or {})
			if opts and opts.textwidth then
				vim.opt_local.textwidth = opts.textwidth
			end
			vim.opt_local.spell = true
		end)
	end)
end

vim.api.nvim_create_autocmd("FileType", {
	group = group,
	pattern = soft,
	callback = function(args)
		enable(args.buf)
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	group = group,
	pattern = vim.tbl_keys(hard),
	callback = function(args)
		enable(args.buf, hard[vim.bo[args.buf].filetype])
	end,
})

-- Markdown rendering
vim.pack.add({
	{ src = "https://github.com/MeanderingProgrammer/render-markdown.nvim" },
})
require("render-markdown").setup({
	latex = { enabled = false },
	heading = { sign = false },
	code = { sign = false },
})
vim.keymap.set("n", "<leader>mr", "<cmd>RenderMarkdown toggle<CR>", { desc = "Toggle Markdown render" })

-- Reading mode
vim.pack.add({ { src = "https://github.com/folke/twilight.nvim" } })
require("twilight").setup({
	dimming = { alpha = 0.3 },
	treesitter = false,
	context = 4,
})

local function reading_mode()
	Snacks.zen({
		on_open = function() require("twilight").enable() end,
		on_close = function() require("twilight").disable() end,
		win = { width = 90, backdrop = { transparent = false } },
		toggles = { dim = false, git_signs = false, diagnostics = false },
	})
	vim.defer_fn(function()
		local wo = vim.wo[0][0]
		wo.number, wo.relativenumber, wo.spell, wo.cursorline = false, false, false, false
		wo.signcolumn, wo.foldcolumn, wo.statuscolumn = "no", "0", ""
	end, 100)
	local function para(dir)
		return function()
			for _ = 1, vim.v.count1 do
				vim.fn.search([[\(^\s*\n\)\@<=\S]], dir == 1 and "W" or "bW")
			end
			vim.cmd("normal! zz")
		end
	end
	local buf = vim.api.nvim_get_current_buf()
	vim.keymap.set("n", "j", para(1), { buffer = buf, desc = "Next paragraph" })
	vim.keymap.set("n", "k", para(-1), { buffer = buf, desc = "Previous paragraph" })
end
vim.keymap.set("n", "<leader>z", reading_mode, { desc = "Reading mode" })
vim.api.nvim_create_autocmd("BufWinEnter", {
	group = vim.api.nvim_create_augroup("local-books", { clear = true }),
	pattern = vim.fn.expand("~") .. "/Documents/books/*.md",
	callback = function(args)
		vim.bo[args.buf].modifiable = false
		vim.schedule(function()
			if vim.api.nvim_win_get_config(0).relative == "" then
				reading_mode()
			end
		end)
	end,
})

-- Restore cursor position
vim.api.nvim_create_autocmd("BufReadPost", {
	group = vim.api.nvim_create_augroup("local-last-position", { clear = true }),
	callback = function(args)
		if vim.bo[args.buf].filetype == "gitcommit" then
			return
		end
		local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
		if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(args.buf) then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

vim.keymap.set("n", "<C-i>", "<C-i>", { desc = "Jump forward" })

-- Harpoon
vim.pack.add({
	{ src = "https://github.com/nvim-lua/plenary.nvim" },
	{ src = "https://github.com/ThePrimeagen/harpoon", version = "harpoon2" },
})
local harpoon = require("harpoon")
harpoon:setup()
vim.keymap.set("n", "<leader>ha", function() harpoon:list():add() end, { desc = "Harpoon add file" })
vim.keymap.set("n", "<leader>he", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end, { desc = "Harpoon quick menu" })
for i = 1, 5 do
	vim.keymap.set("n", "<leader>h" .. i, function() harpoon:list():select(i) end, { desc = "Harpoon file " .. i })
end

-- which-key
vim.pack.add({ { src = "https://github.com/folke/which-key.nvim" } })
require("which-key").setup({ preset = "classic", delay = 300 })
require("which-key").add({
	{ "<leader>h", group = "Harpoon" },
	{ "<leader>m", group = "Markdown" },
	{ "<leader>d", group = "Diff" },
})
