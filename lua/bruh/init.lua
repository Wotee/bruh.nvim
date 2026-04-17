local M = {}

-- Store config options for future use
local config = {}
local active_job_id = nil
local cancel_requested = false
local running_notification = nil

local function clear_running_notification()
	if running_notification ~= nil then
		pcall(vim.notify, "", vim.log.levels.INFO, {
			replace = running_notification,
			timeout = 10,
			hide_from_history = true,
			title = "Bru",
		})
		running_notification = nil
	end

	local ok_notify, notify = pcall(require, "notify")
	if ok_notify and type(notify.dismiss) == "function" then
		pcall(notify.dismiss, { pending = true, silent = true })
	end

	pcall(vim.api.nvim_echo, { { "", "" } }, false, {})
	vim.cmd("redraw")
end

local function deep_get(tbl, ...)
	for _, key in ipairs({ ... }) do
		if type(tbl) ~= "table" then
			return nil
		end
		tbl = tbl[key]
	end
	return tbl
end

local function find_bru_collection_root(start_dir)
	local uv = vim.loop
	local root_markers = { "bruno.json", "opencollection.yml" }

	local function exists(filepath)
		local stat = uv.fs_stat(filepath)
		return stat and stat.type == "file"
	end

	local dir = start_dir
	while dir do
		for _, marker in ipairs(root_markers) do
			local candidate = dir .. "/" .. marker
			if exists(candidate) then
				return dir
			end
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break -- reached root
		end
		dir = parent
	end
	return nil
end

local function complete_env(arg_lead, cmd_line, cursor_pos)
	local buf_path = vim.api.nvim_buf_get_name(0)
	if buf_path == "" then
		vim.notify("Bufpath is empty", vim.log.levels.ERROR)
		return {}
	end

	local file_dir = vim.fn.fnamemodify(buf_path, ":h")
	local collection_root = find_bru_collection_root(file_dir)
	if not collection_root then
		vim.notify("Couldn't find collection root", vim.log.levels.ERROR)
		return {}
	end

	local env_dir = collection_root .. "/environments"
	if vim.fn.isdirectory(env_dir) == 0 then
		vim.notify("Empty environments directory", vim.log.levels.ERROR)
		return {}
	end

	local env_files = vim.fn.glob(env_dir .. "/*.{bru,yml}", false, true)

	local env_names = {}
	for _, f in ipairs(env_files) do
		local name = vim.fn.fnamemodify(f, ":t:r") -- remove path and extension
		if vim.startswith(name, arg_lead) then
			table.insert(env_names, name)
		end
	end
	return env_names
end

M.run_bruno_request = function(env)
	if active_job_id then
		vim.notify("A Bru request is already running", vim.log.levels.WARN)
		return
	end
	cancel_requested = false

	-- Get current buffer file path
	local buf_path = vim.api.nvim_buf_get_name(0)
	if buf_path == "" then
		vim.notify("Buffer is not associated with a file", vim.log.levels.ERROR)
		return
	end
	-- save buffer if modified
	if vim.bo.modified then
		vim.cmd("write")
	end

	-- Output file path
	local output_file = vim.fn.tempname() .. ".json"

	-- Run Bruno CLI using current file as the request source
	local file_dir = vim.fn.fnamemodify(buf_path, ":h")
	local file_name = vim.fn.fnamemodify(buf_path, ":t")

	local collection_root = find_bru_collection_root(file_dir)
	if not collection_root then
		vim.notify("Could not find bruno.json or opencollection.yml in parent directories", vim.log.levels.ERROR)
		return
	end

	local cmd = { "bru", "run", file_name, "--output", output_file, "--format", "json" }
	if env and env ~= "" then
		table.insert(cmd, "--env")
		table.insert(cmd, env)
	end

	local stderr_lines = {}

	active_job_id = vim.fn.jobstart(cmd, {
		cwd = collection_root,
		stdout_buffered = true,
		stderr_buffered = true,
		on_stderr = function(_, data)
			if type(data) ~= "table" then
				return
			end
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(stderr_lines, line)
				end
			end
		end,
		on_exit = vim.schedule_wrap(function(_, code)
			local was_cancelled = cancel_requested
			active_job_id = nil
			cancel_requested = false

			if was_cancelled then
				vim.fn.delete(output_file)
				return
			end

			if code ~= 0 then
				clear_running_notification()
				local message = "Bru CLI failed"
				if #stderr_lines > 0 then
					message = message .. ": " .. stderr_lines[#stderr_lines]
				end
				vim.notify(message, vim.log.levels.ERROR)
				vim.fn.delete(output_file)
				return
			end

			-- Read and parse JSON file
			local ok_read, lines = pcall(vim.fn.readfile, output_file)
			vim.fn.delete(output_file)
			if not ok_read then
				vim.notify("Failed to read Bru output", vim.log.levels.ERROR)
				return
			end

			local ok_decode, parsed = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
			if not ok_decode then
				vim.notify("Failed to parse JSON output", vim.log.levels.ERROR)
				return
			end

			local response_data = deep_get(parsed, 1, "results", 1, "response", "data")
			local response_status_code = deep_get(parsed, 1, "results", 1, "response", "status")
			local response_status_text = deep_get(parsed, 1, "results", 1, "response", "statusText")

			-- If it's a table, pretty-print it
			if type(response_data) == "table" then
				local ok2, encoded = pcall(vim.fn.json_encode, response_data)
				if ok2 then
					-- Pretty-print using jq if available
					local pretty = vim.fn.system({ "jq", "." }, encoded)
					if vim.v.shell_error == 0 then
						response_data = pretty
					else
						response_data = encoded -- fallback
					end
				end
			elseif type(response_data) ~= "string" then
				response_data = response_data == nil and "" or tostring(response_data)
			end

			-- Reuse existing response buffer if it already exists
			local response_buf_name =
				string.format("%s %s", tostring(response_status_code or ""), tostring(response_status_text or ""))
			response_buf_name = vim.trim(response_buf_name)
			if response_buf_name == "" then
				response_buf_name = "Bru Response"
			end

			clear_running_notification()

			local response_bufnr = vim.fn.bufnr(response_buf_name)
			if response_bufnr ~= -1 then
				local winid = vim.fn.bufwinid(response_bufnr)
				if winid ~= -1 then
					vim.api.nvim_set_current_win(winid)
				else
					vim.cmd("new")
					vim.api.nvim_win_set_buf(0, response_bufnr)
				end
			else
				vim.cmd("new")
				vim.api.nvim_buf_set_name(0, response_buf_name)
			end

			vim.cmd("setlocal buftype=nofile bufhidden=hide noswapfile")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(response_data, "\n"))
			vim.cmd("setfiletype json")
		end),
	})

	if active_job_id <= 0 then
		active_job_id = nil
		cancel_requested = false
		clear_running_notification()
		vim.notify("Failed to start Bru CLI", vim.log.levels.ERROR)
		vim.fn.delete(output_file)
		return
	end

	local ok_notify, notification = pcall(vim.notify, "Running Bru request...", vim.log.levels.INFO, {
		title = "Bru",
		timeout = false,
	})
	if ok_notify then
		running_notification = notification
	end
end

M.cancel_bruno_request = function()
	if not active_job_id then
		vim.notify("No Bru request is currently running", vim.log.levels.INFO)
		return
	end

	local job_id = active_job_id
	cancel_requested = true
	clear_running_notification()

	local stopped = vim.fn.jobstop(job_id)
	if stopped == 1 then
		vim.notify("Bru request cancelled", vim.log.levels.INFO)
	else
		cancel_requested = false
		vim.notify("Failed to cancel Bru request", vim.log.levels.WARN)
	end
end

M.setup = function(user_config)
	config = vim.tbl_deep_extend("force", {}, {
		-- Default config (if needed)
	}, user_config or {})
	vim.api.nvim_create_user_command("Bru", function(opts)
		M.run_bruno_request(opts.args)
	end, {
		nargs = "?",
		complete = complete_env,
		desc = "Run bru request in current buffer (optionally with environment)",
	})
	vim.api.nvim_create_user_command("BruCancel", function()
		M.cancel_bruno_request()
	end, {
		desc = "Cancel the running bru request",
	})
end

return M
