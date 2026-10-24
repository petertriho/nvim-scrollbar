# docs/providers/search.md: incremental search marks show while the demo types
# a pattern. Then the demo jumps to the next matches.

Source "scripts/demo/settings.tape"
Output "scripts/demo/out/search.gif"

Hide
Type `DEMO_ENTRY=search "$DEMO_NVIM" --clean -u scripts/demo/init.lua lua/scrollbar/mouse.lua`
Enter
Wait+Screen@30s /(?m)search = \{ incsearch = true \}$/
Show

Sleep 1s
Type "/"
Sleep 300ms
Type@250ms "return"
Sleep 1s
Enter
Sleep 1s
Type "n"
Sleep 700ms
Type "n"
Sleep 700ms
Type "n"
Sleep 1.5s
