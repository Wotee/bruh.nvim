print("loaded bruh.nvim")
local M = {}

M.setup = function()
	-- nothing
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

	-- Read output file
	local file = io.open(output_file, "r")
	if not file then
		vim.notify("Failed to open Bruno output file", vim.log.levels.ERROR)
		return
	end

	local content = file:read("*a")
	file:close()
	-- jq '.[0].results[0].response.data'

	-- Open a new buffer and display output
	vim.cmd("new")
	vim.cmd("setlocal buftype=nofile bufhidden=hide noswapfile")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(content, "\n"))
end

return M
