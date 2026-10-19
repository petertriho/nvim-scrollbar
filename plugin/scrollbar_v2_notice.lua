-- See lua/scrollbar/v2_notice.lua. The check waits until startup ends, so it
-- runs after the setup() call and the handler calls of the user.
if vim.g.loaded_scrollbar_v2_notice then
    return
end
vim.g.loaded_scrollbar_v2_notice = true

if vim.v.vim_did_enter == 1 then
    vim.schedule(function()
        require("scrollbar.v2_notice").check()
    end)
else
    vim.cmd([[autocmd VimEnter * ++once lua vim.schedule(function() require("scrollbar.v2_notice").check() end)]])
end
