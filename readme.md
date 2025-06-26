# bruh.nvim

A Neovim plugin to run [Bruno CLI](https://www.usebruno.com/) requests directly from your editor, with optional environment support and JSON pretty-printing via `jq`.

---

## Prerequisites

- [Bruno CLI](https://www.usebruno.com/) installed globally via npm:
```sh
npm install -g @usebruno/cli
```
- jq installed and available in your shell for JSON pretty-printing (optional but recommended).
- Neovim 0.7+ with Lua support.


## Installation
Using lazy.nvim:

```lua
{
  "Wotee/bruh.nvim",
  cmd = "Bru",
  opts = {},
  build = "npm install -g @usebruno/cli",
}
```
This will install or update the Bruno CLI automatically when the plugin is installed or updated.

## Usage
Open a Bruno request file (usually with .bru extension), then run:

`:Bru` — runs the request in the current buffer.

`:Bru <EnvName>` — runs the request using the environment named <EnvName>.

The plugin will:

Find the root of the Bruno collection by locating collection.bru.

Run the bru CLI command in that folder.

Parse the JSON output and pretty-print it using jq if available.

Open a new buffer in Neovim displaying the results.

### Environment Autocompletion
If your collection root folder contains an environments/ directory with files named like TestEnv.bru, ProdEnv.bru, etc., the plugin will provide autocompletion for environment names in the :Bru command.

## Configuration
Currently, the plugin has no user-configurable options, but it exposes a setup() function for future extensibility.

## License
MIT License

Copyright (c) 2025 Wotee
