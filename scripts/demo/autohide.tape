# docs/visibility.md: with autohide, the scrollbar shows while scrolling and
# hides after one second without activity.

Source "scripts/demo/settings.tape"
Output "scripts/demo/out/autohide.gif"

Hide
Type `DEMO_ENTRY=autohide "$DEMO_NVIM" --clean -u scripts/demo/init.lua lua/scrollbar/mouse.lua`
Enter
Wait+Screen@30s /(?m)autohide = true$/
Show

Sleep 1.2s
Ctrl+D
Sleep 300ms
Ctrl+D
Sleep 300ms
Ctrl+D
Sleep 2s
Ctrl+D
Sleep 300ms
Ctrl+D
Sleep 2s
