# Kiwi Git Permalink

Neovim plugin that copies a permalink for the current file and line range.

## Installation

```lua
return {
    "msga-mmm/kiwi-git-permalink"
}
```

## Usage

```lua
vim.keymap.set("n", "<leader>gp", "<cmd>GitPermalinkCopy<CR>", {
    desc = "Copy git permalink for file",
})

vim.keymap.set("x", "<leader>gp", ":GitPermalinkCopy<CR>", {
    desc = "Copy git permalink for selection",
})
```

It supports:

- GitHub remotes
- GitLab remotes
- file paths with spaces
- copying the URL to your clipboard

## Notes

- The link always uses the current `HEAD` commit.
- The plugin uses the current branch remote if configured, otherwise `origin`.
