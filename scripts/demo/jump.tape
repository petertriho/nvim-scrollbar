# README.md: label mode puts a label on each mark. Two uppercase labels open
# the peek float, <CR> jumps to the peeked mark, and a lowercase label jumps at
# once. <C-o> goes back.

Source "scripts/demo/settings.tape"
Output "scripts/demo/out/jump.gif"

Hide
Type `DEMO_ENTRY=jump "$DEMO_NVIM" --clean -u scripts/demo/init.lua lua/scrollbar/mouse.lua`
Enter
Wait+Screen@30s /(?m)jump\(\)$/
Show

Sleep 1s
Space
Type "j"
Sleep 1.5s
Type "D"
Sleep 1.5s
Type "G"
Sleep 1.5s
Enter
Sleep 1.5s
Space
Type "j"
Sleep 1.2s
Type "a"
Sleep 1.5s
Ctrl+O
Sleep 1.5s
