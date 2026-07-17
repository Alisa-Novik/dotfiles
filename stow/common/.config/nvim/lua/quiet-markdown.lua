local M = {}

local config = {
	source_dim = 0.42,
	is_quiet = function()
		return false
	end,
	suspend_quiet = function() end,
	resume_quiet = function() end,
}

local state = {
	source_buf = nil,
	source_win = nil,
	preview_buf = nil,
	preview_win = nil,
	restore_quiet = false,
	previous_render = false,
	previous_laststatus = nil,
	previous_source_hl_ns = -1,
}

local group = vim.api.nvim_create_augroup("QuietMarkdownPreview", { clear = true })
local shadow_ns = vim.api.nvim_create_namespace("QuietMarkdownSourceShadow")

local function valid_buf(buf)
	return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function clear_state()
	state = {
		source_buf = nil,
		source_win = nil,
		preview_buf = nil,
		preview_win = nil,
		restore_quiet = false,
		previous_render = false,
		previous_laststatus = nil,
		previous_source_hl_ns = -1,
	}
end

local function set_render_state(buf, enabled)
	if valid_buf(buf) then
		pcall(require("render-markdown.core.manager").set_buf, buf, enabled)
	end
end

local function preview_options(win)
	if not valid_win(win) then
		return
	end

	local options = {
		number = false,
		relativenumber = false,
		signcolumn = "no",
		foldcolumn = "0",
		colorcolumn = "",
		list = false,
		wrap = true,
		linebreak = true,
		breakindent = true,
		cursorline = false,
		scrolloff = 3,
		sidescrolloff = 0,
		winfixwidth = false,
	}

	for option, value in pairs(options) do
		pcall(function()
			vim.wo[win][option] = value
		end)
	end
end

local function blend(color, background, ratio)
	local function channel(value, shift)
		return math.floor(value / (2 ^ shift)) % 256
	end

	local red = math.floor(channel(color, 16) * ratio + channel(background, 16) * (1 - ratio))
	local green = math.floor(channel(color, 8) * ratio + channel(background, 8) * (1 - ratio))
	local blue = math.floor(channel(color, 0) * ratio + channel(background, 0) * (1 - ratio))
	return red * 0x10000 + green * 0x100 + blue
end

local protected_highlights = {
	Cursor = true,
	CursorIM = true,
	CursorLineNr = true,
	CurSearch = true,
	IncSearch = true,
	MatchParen = true,
	Search = true,
	TermCursor = true,
	Visual = true,
	VisualNOS = true,
	VertSplit = true,
	WinSeparator = true,
}

local highlight_attributes = {
	"bold",
	"standout",
	"strikethrough",
	"underline",
	"undercurl",
	"underdouble",
	"underdotted",
	"underdashed",
	"italic",
	"reverse",
	"nocombine",
}

local function shadow_source(win)
	if not valid_win(win) then
		return
	end

	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local background = normal.bg or 0x000000
	for _, name in ipairs(vim.fn.getcompletion("", "highlight")) do
		if not protected_highlights[name] then
			local ok, highlight = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
			if ok and next(highlight) ~= nil then
				local dimmed = {}
				if highlight.fg then
					dimmed.fg = blend(highlight.fg, background, config.source_dim)
				end
				if highlight.bg then
					dimmed.bg = blend(highlight.bg, background, math.min(config.source_dim, 0.3))
				end
				if highlight.sp then
					dimmed.sp = blend(highlight.sp, background, config.source_dim)
				end
				for _, attribute in ipairs(highlight_attributes) do
					if highlight[attribute] ~= nil then
						dimmed[attribute] = highlight[attribute]
					end
				end
				pcall(vim.api.nvim_set_hl, shadow_ns, name, dimmed)
			end
		end
	end
	vim.api.nvim_win_set_hl_ns(win, shadow_ns)
end

local function balance_windows()
	if not (valid_win(state.source_win) and valid_win(state.preview_win)) then
		return
	end

	local source_width = vim.api.nvim_win_get_width(state.source_win)
	local preview_width = vim.api.nvim_win_get_width(state.preview_win)
	local available = source_width + preview_width
	local target = math.max(40, math.floor(available * 0.46))
	if source_width ~= target then
		pcall(vim.api.nvim_win_set_width, state.source_win, target)
	end
end

local function restore(resume_quiet)
	local previous = state
	vim.api.nvim_clear_autocmds({ group = group })
	clear_state()

	if previous.previous_laststatus ~= nil then
		vim.o.laststatus = previous.previous_laststatus
	end

	if valid_win(previous.source_win) then
		vim.api.nvim_win_set_hl_ns(previous.source_win, previous.previous_source_hl_ns)
		vim.api.nvim_set_current_win(previous.source_win)
	end
	set_render_state(previous.source_buf, previous.previous_render)

	if resume_quiet and previous.restore_quiet and valid_win(previous.source_win) then
		config.resume_quiet()
	end
end

function M.is_open()
	return valid_buf(state.preview_buf) and valid_win(state.preview_win)
end

function M.is_quiet_suspended()
	return state.restore_quiet
end

---@param opts? { resume_quiet?: boolean }
function M.close(opts)
	if not M.is_open() then
		return false
	end

	opts = opts or {}
	local resume_quiet = opts.resume_quiet ~= false
	local preview_buf = state.preview_buf

	-- Prevent the wipeout autocmd below from restoring twice. render-markdown's
	-- own wipeout hook still runs and re-enables its source buffer; restore()
	-- then returns it to the state it had before opening the preview.
	vim.api.nvim_clear_autocmds({ group = group })
	pcall(vim.api.nvim_buf_delete, preview_buf, { force = true })
	restore(resume_quiet)
	return true
end

local function find_new_window(before)
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if not before[win] then
			return win
		end
	end
end

function M.toggle()
	if M.is_open() then
		M.close()
		return
	end

	local source_buf = vim.api.nvim_get_current_buf()
	if vim.bo[source_buf].filetype ~= "markdown" then
		vim.notify("Quiet Markdown Preview works in Markdown buffers", vim.log.levels.WARN)
		return
	end

	local manager = require("render-markdown.core.manager")
	if not manager.attached(source_buf) then
		vim.notify("render-markdown is not attached to this buffer", vim.log.levels.ERROR)
		return
	end

	local previous_render = require("render-markdown.state").get(source_buf).enabled
	local restore_quiet = config.is_quiet()
	local previous_laststatus

	if restore_quiet then
		config.suspend_quiet()
		previous_laststatus = vim.o.laststatus
		vim.o.laststatus = 0
	end

	local source_win = vim.fn.bufwinid(source_buf)
	if source_win == -1 then
		if previous_laststatus ~= nil then
			vim.o.laststatus = previous_laststatus
		end
		if restore_quiet then
			config.resume_quiet()
		end
		vim.notify("Markdown source window is no longer visible", vim.log.levels.ERROR)
		return
	end

	vim.api.nvim_set_current_win(source_win)
	local windows_before = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		windows_before[win] = true
	end

	require("render-markdown").preview()
	local preview_win = find_new_window(windows_before)
	if not valid_win(preview_win) then
		set_render_state(source_buf, previous_render)
		if previous_laststatus ~= nil then
			vim.o.laststatus = previous_laststatus
		end
		if restore_quiet then
			config.resume_quiet()
		end
		vim.notify("Unable to open the Markdown preview window", vim.log.levels.ERROR)
		return
	end

	local preview_buf = vim.api.nvim_win_get_buf(preview_win)
	local previous_source_hl_ns = vim.api.nvim_get_hl_ns({ winid = source_win })
	state = {
		source_buf = source_buf,
		source_win = source_win,
		preview_buf = preview_buf,
		preview_win = preview_win,
		restore_quiet = restore_quiet,
		previous_render = previous_render,
		previous_laststatus = previous_laststatus,
		previous_source_hl_ns = previous_source_hl_ns,
	}

	preview_options(preview_win)
	shadow_source(source_win)
	vim.api.nvim_set_current_win(source_win)
	balance_windows()

	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		desc = "Keep Markdown source and rendered preview balanced",
		callback = function()
			vim.defer_fn(balance_windows, 50)
		end,
	})

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		desc = "Refresh Markdown source shadow after colorscheme changes",
		callback = function()
			vim.schedule(function()
				shadow_source(state.source_win)
			end)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		buffer = preview_buf,
		once = true,
		desc = "Restore QuietZen after closing Markdown preview",
		callback = function()
			vim.schedule(function()
				if state.preview_buf == preview_buf then
					restore(true)
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		buffer = source_buf,
		once = true,
		desc = "Close rendered preview with its Markdown source",
		callback = function()
			vim.schedule(function()
				if M.is_open() then
					M.close({ resume_quiet = false })
				end
			end)
		end,
	})
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
	pcall(vim.api.nvim_del_user_command, "QuietMarkdown")
	vim.api.nvim_create_user_command("QuietMarkdown", M.toggle, {
		desc = "Toggle raw Markdown and rendered preview side-by-side",
	})
end

return M
