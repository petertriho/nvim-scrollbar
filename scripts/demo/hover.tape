# README.md: with hover = true, the peek float opens when the pointer rests on
# a mark. VHS cannot move the pointer, so timers of the demo entry move it. The
# winbar tells where the pointer is.

Source "scripts/demo/settings.tape"
Output "scripts/demo/out/hover.gif"

Hide
Type `DEMO_ENTRY=hover "$DEMO_NVIM" --clean -u scripts/demo/init.lua lua/scrollbar/mouse.lua`
Enter
Wait+Screen@30s /(?m)hover = true$/
Show

Sleep 10.5s
