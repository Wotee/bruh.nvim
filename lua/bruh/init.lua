local M = {}

-- Store confit options for future use
local config = {}

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
	local function exists(filepath)
		local stat = uv.fs_stat(filepath)
		return stat and stat.type == "file"
	end

	local dir = start_dir
	while dir do
		local candidate = dir .. "/collection.bru"
		if exists(candidate) then
			return dir
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
		return {}
	end

	local file_dir = vim.fn.fnamemodify(buf_path, ":h")
	local collection_root = find_bru_collection_root(file_dir)
	if not collection_root then
		return {}
	end

	local env_dir = collection_root .. "/environments"
	if vim.fn.isdirectory(env_dir) == 0 then
		return {}
	end

	local env_files = vim.fn.glob(env_dir .. "/*.bru", false, true)
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
	local output_file = "/tmp/bruno_output.json"

	-- Run Bruno CLI using current file as the request source
	local file_dir = vim.fn.fnamemodify(buf_path, ":h")
	local file_name = vim.fn.fnamemodify(buf_path, ":t")

	local collection_root = find_bru_collection_root(file_dir)
	if not collection_root then
		vim.notify("Could not find collection.bru in parent directories", vim.log.levels.ERROR)
		return
	end

	local cmd
	if env and env ~= "" then
		cmd = string.format(
			"(cd %s && bru run %s --reporter-json %s --env %s)",
			collection_root,
			file_name,
			output_file,
			env
		)
	else
		cmd = string.format("(cd %s && bru run %s --reporter-json %s)", collection_root, file_name, output_file)
	end

	local result = os.execute(cmd)
	if result ~= 0 then
		vim.notify("Bru CLI failed", vim.log.levels.ERROR)
		return
	end

	-- Read and parse JSON file
	local lines = vim.fn.readfile(output_file)
	local ok, parsed = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
	if not ok then
		vim.notify("Failed to parse JSON output", vim.log.levels.ERROR)
		return
	end
	local response_data = deep_get(parsed, 1, "results", 1, "response", "data")
	-- If it's a table, pretty-print it
	if type(response_data) == "table" then
		local ok2, encoded = pcall(vim.fn.json_encode, response_data)
		if ok2 then
			-- Pretty-print using jq if available
			local handle = io.popen("jq .", "w")
			if handle then
				handle:write(encoded)
				handle:close()
				local pretty = vim.fn.system("echo " .. vim.fn.shellescape(encoded) .. " | jq .")
				if vim.v.shell_error == 0 then
					response_data = pretty
				else
					response_data = encoded -- fallback
				end
			else
				response_data = encoded
			end
		end
	end

	-- Open a new buffer and display output
	vim.cmd("new")
	vim.cmd("setlocal buftype=nofile bufhidden=hide noswapfile")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(response_data, "\n"))
	vim.cmd("setfiletype json")
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
end

return M
