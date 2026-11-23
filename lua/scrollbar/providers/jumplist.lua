local position_targets = require("scrollbar.providers.position_targets")

---@param entry? table An entry of getjumplist()
---@param bufnr integer
---@return integer?
local function line_in(entry, bufnr)
    -- A target in another buffer gets no mark, because the key leaves the
    -- buffer of the window.
    if entry ~= nil and entry.bufnr == bufnr then
        return entry.lnum
    end
    return nil
end

return position_targets.provider({
    name = "jumplist",
    older = "JumpOlder",
    newer = "JumpNewer",
    -- An edit moves the jumplist entries only when it inserts or deletes
    -- lines.
    every_edit = false,
    read = function(bufnr)
        local jumps = vim.fn.getjumplist()
        local older, newer = position_targets.targets(jumps[1], jumps[2])
        return line_in(older, bufnr), line_in(newer, bufnr)
    end,
})
