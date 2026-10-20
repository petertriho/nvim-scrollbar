# README hero: the default scrollbar and minimap while the demo scrolls,
# searches, and jumps through lua/scrollbar/mouse.lua.

Source "scripts/demo/settings.tape"
Output "scripts/demo/out/hero.gif"

Hide
Type `DEMO_ENTRY=hero "$DEMO_NVIM" --clean -u scripts/demo/init.lua lua/scrollbar/mouse.lua`
Enter
Wait+Screen@30s /(?m)nvim-scrollbar$/
Show

Sleep 1s
Ctrl+D
Sleep 300ms
Ctrl+D
Sleep 300ms
Ctrl+D
Sleep 300ms
Ctrl+D
Sleep 800ms
Type "/pcall"
Sleep 400ms
Enter
Sleep 1s
Type "n"
Sleep 700ms
Type "n"
Sleep 700ms
Type "n"
Sleep 700ms
Type "n"
Sleep 700ms
Type "G"
Sleep 1s
Type "gg"
Sleep 1.5s
