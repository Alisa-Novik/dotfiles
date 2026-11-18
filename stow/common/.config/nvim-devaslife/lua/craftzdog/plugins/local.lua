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
