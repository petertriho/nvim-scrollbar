# Providers

Built-in providers publish typed marks for eligible source windows. Provider
configuration controls collection; `layout` controls placement and width.

## Built-ins

| Provider | Default | Scope | Mark types | Dependency |
| --- | --- | --- | --- | --- |
| [`cursor`](cursor.md) | on | Window | `Cursor` | None |
| [`diagnostic`](diagnostic.md) | on | Buffer | `Error`, `Warn`, `Info`, `Hint`, `Misc` | None |
| [`search`](search.md) | on | Buffer | `Search` | None |
| [`marks`](marks.md) | on | Buffer | `Mark` | None |
| [`gitsigns`](gitsigns.md) | off | Buffer | `GitAdd`, `GitChange`, `GitDelete` | gitsigns.nvim |
| [`mini_diff`](mini_diff.md) | off | Buffer | `MiniDiffAdd`, `MiniDiffChange`, `MiniDiffDelete` | mini.diff |
| [`signify`](signify.md) | off | Buffer | `SignifyAdd`, `SignifyChange`, `SignifyDelete` | vim-signify |
| [`vgit`](vgit.md) | off | Buffer | `VGitAdd`, `VGitChange`, `VGitDelete` | vgit.nvim |
| [`ale`](ale.md) | off | Buffer | `Error`, `Warn` | ALE |
| [`coc`](coc.md) | off | Buffer | `Error`, `Warn`, `Info`, `Hint` | coc.nvim |

```lua
providers = {
    cursor = true,
    diagnostic = true,
    search = { incsearch = false, backend = "worker" },
    marks = { letters = true, numbers = false },
    gitsigns = false,
    mini_diff = false,
    signify = false,
    vgit = false,
    ale = false,
    coc = false,
}
```

`search` accepts `incsearch` and `backend` (`"worker"` or `"sync"`). Omitting
`incsearch` follows `vim.o.incsearch`. `marks` accepts only `letters` and
`numbers`. All other built-ins are booleans. Unknown provider keys are errors;
register custom data sources through the [custom provider API](custom.md).

Provider output types are styled under `marks.<Type>` with `text`, `priority`,
and `highlight`. Route types into explicit or catch-all lanes under `layout`.
Lower numeric priority wins only within one mark lane; separate layers follow
their bottom-to-top stack order.

Providers refresh initially during setup. `:ScrollbarRefresh` refreshes every
eligible displayed buffer and source window, then queues rendering without
revealing autohide-concealed floats. Optional integrations safely emit no marks
when their dependency is unavailable.

Multiple diff providers may be enabled together. Their data remains separately
owned but can overlap visually; use typed layout lanes, priorities, or disable
duplicated sources.

## Related

- [Configuration](../configuration.md)
- [Layout and geometry](../layout-and-geometry.md)
- [Custom providers](custom.md)
