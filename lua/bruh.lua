print("loaded bruh.nvim")
local M = {}

M.setup = function()
	-- nothing
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

M.test = function()
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
	local cmd = string.format("bru run %s --reporter-json %s", buf_path, output_file)
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

return M
