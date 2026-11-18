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

-- Rendered Markdown in-buffer (raw text returns on the cursor line / in insert mode)
vim.pack.add({
	{ src = "https://github.com/MeanderingProgrammer/render-markdown.nvim" },
})
require("render-markdown").setup({
	latex = { enabled = false },
	heading = { sign = false },
	code = { sign = false },
})
vim.keymap.set("n", "<leader>mr", "<cmd>RenderMarkdown toggle<CR>", { desc = "Toggle Markdown render" })

-- Reading mode for books: centered narrow column, no numbers/spell/signs.
-- Auto-enabled for ~/Documents/books/*; toggle anywhere with <leader>z.
vim.pack.add({ { src = "https://github.com/folke/twilight.nvim" } })
require("twilight").setup({
	dimming = { alpha = 0.3 },
	-- line mode (treesitter would light only the exact paragraph and ignore context).
	-- Paragraphs are single lines separated by blanks, so ±2 lines = the paragraph
	-- above and below; the range then grows to the surrounding blank lines.
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
	-- pencil/statuscolumn set these asynchronously, so apply after them
	vim.defer_fn(function()
		local wo = vim.wo[0][0]
		wo.number, wo.relativenumber, wo.spell, wo.cursorline = false, false, false, false
		wo.signcolumn, wo.foldcolumn, wo.statuscolumn = "no", "0", ""
	end, 100)
	-- j/k jump between paragraphs and keep the current one centered
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
		vim.schedule(reading_mode)
	end,
})

-- Reopen any file at the last cursor position
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
