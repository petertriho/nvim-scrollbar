# README.md: the glance window lists the marks. The preview follows the
# selection. <Tab> focuses the preview for an edit, <C-w>p returns to the
# list, and <CR> jumps.

Source "scripts/demo/settings.tape"
Output "scripts/demo/out/glance.gif"

Hide
Type `DEMO_ENTRY=glance "$DEMO_NVIM" --clean -u scripts/demo/init.lua lua/scrollbar/mouse.lua`
Enter
Wait+Screen@30s /(?m)glance\(\)$/
Show

Sleep 1s
Space
Type "g"
Sleep 1.5s
Type@500ms "jjj"
Sleep 1s
Tab
Sleep 800ms
Type "O-- edited in the preview"
Escape
Sleep 1s
Ctrl+W
Type "p"
Sleep 1s
Type@500ms "jj"
Sleep 800ms
Enter
Sleep 2s
