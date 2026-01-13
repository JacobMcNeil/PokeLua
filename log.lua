-- simple file logger
local M = {}

local function ts()
    return os.date("%Y-%m-%d %H:%M:%S")
end

function M.log(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts+1] = tostring(select(i, ...))
    end
    local line = table.concat(parts, "\t")
    local f, err = io.open("debug.log", "a")
    if f then
        f:write(string.format("[%s] %s\n", ts(), line))
        f:close()
    else
        -- fallback to stdout if file can't be written
        print("log error:", err, line)
    end
end

return M
