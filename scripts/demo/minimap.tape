# docs/minimap/README.md: the minimap scrolls with the source window and tints
# the viewport.

Source "scripts/demo/settings.tape"
Output "scripts/demo/out/minimap.gif"

Hide
Type `DEMO_ENTRY=minimap "$DEMO_NVIM" --clean -u scripts/demo/init.lua lua/scrollbar/mouse.lua`
Enter
Wait+Screen@30s /(?m)minimap = \{ enabled = true \}$/
Show

Sleep 1s
Ctrl+D
Sleep 250ms
Ctrl+D
Sleep 250ms
Ctrl+D
Sleep 250ms
Ctrl+D
Sleep 250ms
Ctrl+D
Sleep 250ms
Ctrl+D
Sleep 800ms
Type "300G"
Sleep 1.2s
Type "G"
Sleep 1.2s
Type "gg"
Sleep 1.5s
