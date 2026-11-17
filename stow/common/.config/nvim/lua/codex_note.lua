local M = {}

local defaults = {
	max_scope_lines = 80,
	max_scope_bytes = 12000,
	target_search_lines = 12,
	executable = nil,
	working_dir = nil,
}

local config = vim.deepcopy(defaults)
local namespace = vim.api.nvim_create_namespace("codex-note")
local jobs = {}

local instruction = [[
Complete exactly one answer placeholder in a Markdown or plain-text note.

The text on stdin is the complete question scope. Answer that scope only.
Return only the answer body that belongs after `A: `.
Do not repeat or renumber the question, and do not add an `A:` prefix.
Follow formatting or depth requested by the question; otherwise use concise, clear Markdown.
Do not inspect, discuss, or modify files. Do not describe your process or tools.
]]

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Codex note" })
end

local function is_blank(line)
	return line:match("^%s*$") ~= nil
end

local function is_empty_answer(line)
	return line:match("^%s*[Aa]:%s*$") ~= nil
end

local function is_any_answer(line)
	return line:match("^%s*[Aa]:") ~= nil
end

local function is_question_start(line)
	return line:match("^%s*%d+[%.)]%s+%S") ~= nil
		or line:match("^%s*[Qq]:%s*%S") ~= nil
		or line:match("^%s*[Qq]uestion:%s*%S") ~= nil
end

local function make_scope(buf, start_row, end_row)
	local lines = vim.api.nvim_buf_get_lines(buf, start_row, end_row, false)
	local leading = 0
	while leading < #lines and is_blank(lines[leading + 1]) do
		leading = leading + 1
	end

	local trailing = #lines
	while trailing > leading and is_blank(lines[trailing]) do
		trailing = trailing - 1
	end

	if trailing <= leading then
		return nil, "No question text found before the empty A: line"
	end

	local scoped = {}
	for index = leading + 1, trailing do
		table.insert(scoped, lines[index])
	end

	if #scoped > config.max_scope_lines then
		return nil, ("Question scope is %d lines; select at most %d lines explicitly"):format(
			#scoped,
			config.max_scope_lines
		)
	end

	local text = table.concat(scoped, "\n")
	if #text > config.max_scope_bytes then
		return nil, ("Question scope is too large (%d bytes; limit %d)"):format(#text, config.max_scope_bytes)
	end

	return {
		start_row = start_row + leading,
		end_row = start_row + trailing,
		line_count = #scoped,
		text = text,
	}
end

local function auto_scope(buf, answer_row)
	local first_row = math.max(0, answer_row - config.max_scope_lines)
	local start_row
	local boundary_row = first_row

	for row = answer_row - 1, first_row, -1 do
		local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
		if is_any_answer(line) then
			boundary_row = row + 1
			break
		end
		if is_question_start(line) then
			start_row = row
			break
		end
	end

	if not start_row then
		local row = answer_row - 1
		while row >= boundary_row do
			local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
			if not is_blank(line) then
				break
			end
			row = row - 1
		end

		if row < boundary_row then
			return nil, "No question text found before the empty A: line"
		end

		while row >= boundary_row do
			local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
			if is_blank(line) or is_any_answer(line) then
				break
			end
			row = row - 1
		end
		start_row = row + 1
	end

	return make_scope(buf, start_row, answer_row)
end

local function range_scope(buf, first_row, last_row)
	local line_count = vim.api.nvim_buf_line_count(buf)
	first_row = math.max(0, math.min(first_row, line_count - 1))
	last_row = math.max(first_row, math.min(last_row, line_count - 1))

	local answer_row
	for row = first_row, last_row do
		local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
		if is_empty_answer(line) then
			answer_row = row
			break
		end
	end

	local scope_end = last_row + 1
	if answer_row then
		scope_end = answer_row
	else
		local final_row = math.min(line_count - 1, last_row + config.target_search_lines)
		for row = last_row + 1, final_row do
			local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
			if is_empty_answer(line) then
				answer_row = row
				break
			end
		end
	end

	if not answer_row then
		return nil, nil, ("No empty A: line in or within %d lines after the selection"):format(
			config.target_search_lines
		)
	end

	local scope, err = make_scope(buf, first_row, scope_end)
	return scope, answer_row, err
end

local function clean_answer(stdout)
	local answer = (stdout or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
	answer = vim.trim(answer)
	answer = answer:gsub("^[Aa]:[ \t]*", "", 1)
	answer = vim.trim(answer)
	if answer == "" then
		return nil, "Codex returned an empty answer"
	end
	return answer
end

local function clear_mark(buf, state)
	if vim.api.nvim_buf_is_valid(buf) and state.mark then
		pcall(vim.api.nvim_buf_del_extmark, buf, namespace, state.mark)
	end
end

local function fail(buf, state, message)
	if jobs[buf] == state then
		jobs[buf] = nil
	end
	clear_mark(buf, state)
	notify(message, vim.log.levels.ERROR)
end

local function save_buffer(buf)
	if vim.api.nvim_buf_get_name(buf) == "" or vim.bo[buf].buftype ~= "" then
		return true
	end

	local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
		vim.cmd("silent update")
	end)
	if not ok then
		notify("Answer inserted, but the file could not be saved: " .. tostring(err), vim.log.levels.WARN)
	end
	return ok
end

local function insert_result(buf, state, result)
	if jobs[buf] ~= state then
		return
	end
	if result.code ~= 0 then
		local detail = vim.trim(result.stderr or "")
		if #detail > 900 then
			detail = detail:sub(-900)
		end
		fail(buf, state, detail ~= "" and ("Codex failed: " .. detail) or ("Codex exited with code " .. result.code))
		return
	end

	local answer, answer_err = clean_answer(result.stdout)
	if not answer then
		fail(buf, state, answer_err)
		return
	end

	if not vim.api.nvim_buf_is_loaded(buf) then
		fail(buf, state, "The note buffer was closed before Codex finished")
		return
	end

	local position = vim.api.nvim_buf_get_extmark_by_id(buf, namespace, state.mark, {})
	if #position < 2 then
		fail(buf, state, "The A: placeholder was removed before Codex finished")
		return
	end

	local row = position[1]
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
	if not is_empty_answer(line) then
		fail(buf, state, "The A: placeholder changed while Codex was running; nothing was inserted")
		return
	end
	if not vim.bo[buf].modifiable then
		fail(buf, state, "The note buffer is no longer modifiable")
		return
	end

	clear_mark(buf, state)
	jobs[buf] = nil

	local answer_lines = vim.split(answer, "\n", { plain = true })
	if not line:match("%s$") then
		answer_lines[1] = " " .. answer_lines[1]
	end

	local ok, err = pcall(vim.api.nvim_buf_set_text, buf, row, #line, row, #line, answer_lines)
	if not ok then
		notify("Could not insert the Codex answer: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	save_buffer(buf)
	notify(("Answer inserted from lines %d–%d"):format(state.scope.start_row + 1, state.scope.end_row))
end

local function executable_path()
	if config.executable and config.executable ~= "" then
		return config.executable
	end
	local path = vim.fn.exepath("codex")
	if path == "" then
		return nil
	end
	return path
end

local function working_dir()
	local path = config.working_dir or (vim.fn.stdpath("cache") .. "/codex-note")
	if vim.fn.isdirectory(path) == 0 then
		local created = vim.fn.mkdir(path, "p")
		if created == 0 and vim.fn.isdirectory(path) == 0 then
			return nil, "Could not create isolated Codex working directory: " .. path
		end
	end
	return path
end

function M.complete(opts)
	opts = opts or {}
	local buf = opts.bufnr or vim.api.nvim_get_current_buf()
	if buf == 0 then
		buf = vim.api.nvim_get_current_buf()
	end
	if not vim.api.nvim_buf_is_loaded(buf) then
		notify("The current buffer is not loaded", vim.log.levels.ERROR)
		return false
	end
	if not vim.bo[buf].modifiable then
		notify("The current buffer is not modifiable", vim.log.levels.ERROR)
		return false
	end
	if jobs[buf] then
		notify("Codex is already answering in this buffer", vim.log.levels.WARN)
		return false
	end

	local scope
	local answer_row
	local err
	if opts.range then
		scope, answer_row, err = range_scope(buf, opts.range[1], opts.range[2])
	else
		answer_row = opts.answer_row or (vim.api.nvim_win_get_cursor(0)[1] - 1)
		local answer_line = vim.api.nvim_buf_get_lines(buf, answer_row, answer_row + 1, false)[1] or ""
		if not is_empty_answer(answer_line) then
			notify("Put the cursor on an empty A: line, or visually select the question", vim.log.levels.WARN)
			return false
		end
		scope, err = auto_scope(buf, answer_row)
	end

	if not scope then
		notify(err or "Could not determine the question scope", vim.log.levels.WARN)
		return false
	end

	local executable = executable_path()
	if not executable then
		notify("Codex CLI was not found in Neovim's PATH", vim.log.levels.ERROR)
		return false
	end
	local cwd, cwd_err = working_dir()
	if not cwd then
		notify(cwd_err, vim.log.levels.ERROR)
		return false
	end

	local answer_line = vim.api.nvim_buf_get_lines(buf, answer_row, answer_row + 1, false)[1] or ""
	local mark = vim.api.nvim_buf_set_extmark(buf, namespace, answer_row, #answer_line, {
		right_gravity = true,
		virt_text = {
			{ ("  Codex… lines %d–%d"):format(scope.start_row + 1, scope.end_row), "DiagnosticInfo" },
		},
		virt_text_pos = "eol",
	})

	local state = {
		mark = mark,
		scope = scope,
	}
	jobs[buf] = state

	local command = {
		executable,
		"exec",
		"--ephemeral",
		"--sandbox",
		"read-only",
		"--skip-git-repo-check",
		"--color",
		"never",
		instruction,
	}

	local ok, process_or_err = pcall(vim.system, command, {
		cwd = cwd,
		stdin = scope.text,
		text = true,
	}, function(result)
		vim.schedule(function()
			insert_result(buf, state, result)
		end)
	end)

	if not ok then
		fail(buf, state, "Could not start Codex: " .. tostring(process_or_err))
		return false
	end

	state.process = process_or_err
	notify(("Answering lines %d–%d…"):format(scope.start_row + 1, scope.end_row))
	return true
end

function M.cancel(buf, silent)
	buf = buf or vim.api.nvim_get_current_buf()
	if buf == 0 then
		buf = vim.api.nvim_get_current_buf()
	end
	local state = jobs[buf]
	if not state then
		if not silent then
			notify("No Codex answer is running in this buffer", vim.log.levels.WARN)
		end
		return false
	end

	jobs[buf] = nil
	clear_mark(buf, state)
	if state.process then
		pcall(function()
			state.process:kill(15)
		end)
	end
	if not silent then
		notify("Codex answer cancelled")
	end
	return true
end

function M.is_running(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if buf == 0 then
		buf = vim.api.nvim_get_current_buf()
	end
	return jobs[buf] ~= nil
end

function M.scope_for_answer(buf, answer_row)
	return auto_scope(buf, answer_row)
end

function M.scope_for_range(buf, first_row, last_row)
	return range_scope(buf, first_row, last_row)
end

local function complete_from_insert(buf)
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
	if not is_empty_answer(line) then
		local ok, cmp = pcall(require, "cmp")
		if ok then
			cmp.complete()
		end
		return
	end

	vim.cmd.stopinsert()
	vim.schedule(function()
		M.complete({ bufnr = buf, answer_row = row })
	end)
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

	pcall(vim.api.nvim_del_user_command, "CodexComplete")
	pcall(vim.api.nvim_del_user_command, "CodexCancel")

	vim.api.nvim_create_user_command("CodexComplete", function(args)
		local opts_for_command = {}
		if args.range > 0 then
			opts_for_command.range = { args.line1 - 1, args.line2 - 1 }
		end
		M.complete(opts_for_command)
	end, {
		range = true,
		desc = "Fill an empty A: line with a scoped Codex answer",
	})

	vim.api.nvim_create_user_command("CodexCancel", function()
		M.cancel()
	end, { desc = "Cancel the Codex answer running in this buffer" })

	vim.keymap.set("n", "<leader>cq", M.complete, { desc = "[C]odex answer [Q]uestion" })
	vim.keymap.set("x", "<leader>cq", function()
		local first_row = vim.fn.line("v") - 1
		local last_row = vim.api.nvim_win_get_cursor(0)[1] - 1
		if first_row > last_row then
			first_row, last_row = last_row, first_row
		end
		vim.cmd("normal! \27")
		M.complete({ range = { first_row, last_row } })
	end, { desc = "[C]odex answer selected [Q]uestion" })
	vim.keymap.set("n", "<leader>cx", M.cancel, { desc = "Cancel Code[x] answer" })
	vim.keymap.set("i", "<C-g>q", function()
		complete_from_insert(vim.api.nvim_get_current_buf())
	end, { desc = "Codex answer question at A:" })

	local group = vim.api.nvim_create_augroup("codex-note", { clear = true })
	vim.api.nvim_create_autocmd("InsertEnter", {
		group = group,
		desc = "Use the normal completion key to fill empty A: lines with Codex",
		callback = function(args)
			local buf = args.buf
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end
				vim.keymap.set("i", "<C-Space>", function()
					complete_from_insert(buf)
				end, { buffer = buf, desc = "Complete text, or ask Codex on an empty A: line" })
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(args)
			M.cancel(args.buf, true)
		end,
	})
end

return M
