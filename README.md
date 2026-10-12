# bot_calc.nvim

A small Neovim programmer calculator for inspecting and editing values up to 64 bits.
It opens a floating register view with live hexadecimal, unsigned decimal, signed
decimal, and octal representations.

## Install

With `lazy.nvim`:

```lua
{ "your-name/bot_calc", config = function()
  require("bot_calc").setup()
end }
```

Or add this directory to `runtimepath`. The plugin defines `:BotCalc [hex-value]`.
For example, `:BotCalc 0x000000000000ff0f` opens the inspector initialized to that
value; without an argument it opens at zero. You can also call
`require("bot_calc").open({ value = "ff0f", width = 16 })`.

## Controls

| Key | Action |
| --- | --- |
| `h` / `l`, arrows | Move bit cursor |
| `j` / `k` | Move by one byte |
| `Space`, `x`, `~` | Toggle selected bit |
| `s` | Switch displayed byte order |
| `y` / `d` | Copy hexadecimal / decimal value to `+` |
| `Ctrl-h` / `Ctrl-l` | Shift left / right |
| `r` / `R` | Rotate left / right |
| `i` | Invert all bits in the selected word size |
| `8` / `1` / `3` / `6` | Select 8 / 16 / 32 / 64 bit width |
| `q` | Close the floating window |

The grid labels bits by their index (0 is the least significant bit). Endian
switching changes the byte display order while preserving the numeric value.
