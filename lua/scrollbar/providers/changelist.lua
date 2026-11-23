local position_targets = require("scrollbar.providers.position_targets")

return position_targets.provider({
    name = "changelist",
    older = "ChangeOlder",
    newer = "ChangeNewer",
    -- Each edit can add an entry to the change list.
    every_edit = true,
    read = function()
        local changes = vim.fn.getchangelist()
        local older, newer = position_targets.targets(changes[1], changes[2] --[[@as integer]])
        return older and older.lnum, newer and newer.lnum
    end,
})
