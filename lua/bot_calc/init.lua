local M = {}
local bit = bit or bit32

if not bit then
  error("bot_calc requires Neovim's bit library")
end

local state = { hi = 0, lo = 0, width = 64, little_endian = false, cursor = 0 }
local buf, win, ns

local function u32(n) return bit.band(n, 0xffffffff) end
local function mask()
  if state.width == 64 then return 0xffffffff, 0xffffffff end
  if state.width <= 32 then
    return 0, state.width == 32 and 0xffffffff or bit.lshift(1, state.width) - 1
  end
  return state.width == 64 and 0xffffffff or bit.lshift(1, state.width - 32) - 1, 0xffffffff
end
local function apply_mask()
  local mh, ml = mask()
  state.hi, state.lo = bit.band(state.hi, mh), bit.band(state.lo, ml)
end

-- Decimal conversion without relying on Lua's signed 64-bit numeric range.
local function to_base(hi, lo, base)
  local limbs = { bit.rshift(hi, 16), bit.band(hi, 0xffff), bit.rshift(lo, 16), bit.band(lo, 0xffff) }
  local out = ""
  repeat
    local rem = 0
    for i = 1, 4 do
      local n = rem * 65536 + limbs[i]
      limbs[i], rem = math.floor(n / base), n % base
    end
    out = string.sub("0123456789abcdef", rem + 1, rem + 1) .. out
  until limbs[1] == 0 and limbs[2] == 0 and limbs[3] == 0 and limbs[4] == 0
  return out
end
local function decimal(hi, lo) return to_base(hi, lo, 10) end

local function as_hex()
  if state.width <= 32 then return string.format("0x%0" .. math.ceil(state.width / 4) .. "x", state.lo) end
  return string.format("0x%08x%08x", state.hi, state.lo)
end

local function bit_at(index)
  if index < 32 then return bit.band(bit.rshift(state.lo, index), 1) end
  return bit.band(bit.rshift(state.hi, index - 32), 1)
end

local function set_bit(index, value)
  local maskbit = bit.lshift(1, index % 32)
  local field = index < 32 and "lo" or "hi"
  if value == 1 then state[field] = bit.bor(state[field], maskbit)
  else state[field] = bit.band(state[field], bit.bnot(maskbit)) end
end

local function display_indices()
  local bytes = {}
  for b = 0, state.width / 8 - 1 do bytes[#bytes + 1] = b end
  if not state.little_endian then
    local reversed = {}
    for i = #bytes, 1, -1 do reversed[#reversed + 1] = bytes[i] end
    bytes = reversed
  end
  local bits = {}
  for _, byte in ipairs(bytes) do
    for n = 7, 0, -1 do bits[#bits + 1] = byte * 8 + n end
  end
  return bytes, bits
end

local function signed_decimal()
  local sign = state.width <= 32 and bit.band(bit.rshift(state.lo, state.width - 1), 1)
    or bit.band(bit.rshift(state.hi, state.width - 33), 1)
  if sign == 0 then return decimal(state.hi, state.lo) end
  local hi, lo = bit.bnot(state.hi), bit.bnot(state.lo)
  local mh, ml = mask()
  hi, lo = bit.band(hi, mh), bit.band(lo, ml)
  lo = u32(lo + 1)
  if lo == 0 then hi = u32(hi + 1) end
  return "-" .. decimal(hi, lo)
end

local function render()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local bytes, indices = display_indices()
  local lines = {
    string.format("%d-bit Register Inspector  [%s endian]", state.width, state.little_endian and "little" or "big"),
    "Hex:      " .. as_hex(),
    "Unsigned: " .. decimal(state.hi, state.lo),
    "Signed:   " .. signed_decimal(),
    "Octal:    0" .. to_base(state.hi, state.lo, 8),
    "",
  }
  local bitline, indexline = "", ""
  for i, index in ipairs(indices) do
    local value = tostring(bit_at(index))
    if index == state.cursor then value = "[" .. value .. "]" else value = " " .. value .. " " end
    bitline = bitline .. value
    indexline = indexline .. string.format("%2d ", index)
    if i % 8 == 0 then
      local byte = bytes[math.floor((i - 1) / 8) + 1]
      lines[#lines + 1] = string.format("Byte %d%s", byte, byte == state.width / 8 - 1 and " (MSB)" or byte == 0 and " (LSB)" or "")
      lines[#lines + 1] = indexline
      lines[#lines + 1] = bitline
      lines[#lines + 1] = ""
      bitline, indexline = "", ""
    end
  end
  lines[#lines + 1] = "h/l or arrows move | Space/x/~ toggle | s endian | y copy hex | d copy decimal"
  lines[#lines + 1] = "Ctrl-h/l shift | r/R rotate | i invert | 8/1/3/6 choose width | q close"
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  local width = vim.api.nvim_win_get_width(win)
  vim.api.nvim_win_set_cursor(win, { math.min(9, vim.api.nvim_buf_line_count(buf)), 1 })
  -- Highlight the active bit cell using the character position in the rendered row.
  local shown = state.little_endian and state.cursor or (state.width - 1 - state.cursor)
  local row = 9 + math.floor(shown / 8) * 4
  local col = (shown % 8) * 3
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "Visual", row - 1, col, col + 3)
  pcall(vim.api.nvim_win_set_cursor, win, { row, col })
  if width < 45 then vim.api.nvim_win_set_width(win, 45) end
end

local function move(delta)
  local count = state.width
  local visual = state.little_endian and state.cursor or (count - 1 - state.cursor)
  visual = (visual + delta) % count
  state.cursor = state.little_endian and visual or (count - 1 - visual)
  render()
end
local function toggle()
  set_bit(state.cursor, bit.bxor(bit_at(state.cursor), 1)); render()
end
local function shift(left)
  if left then state.hi = u32(bit.bor(bit.lshift(state.hi, 1), bit.rshift(state.lo, 31))); state.lo = u32(bit.lshift(state.lo, 1))
  else state.lo = u32(bit.bor(bit.rshift(state.lo, 1), bit.lshift(state.hi, 31))); state.hi = u32(bit.rshift(state.hi, 1)) end
  apply_mask(); render()
end
local function rotate(left)
  local wrap = left and bit_at(state.width - 1) or bit_at(0)
  shift(left); set_bit(left and 0 or state.width - 1, wrap); render()
end
local function map(lhs, rhs, fn)
  vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = rhs })
end

function M.open(opts)
  opts = opts or {}
  if opts.value then
    local value = tostring(opts.value):gsub("^0[xX]", "")
    value = value:match("([%da-fA-F]+)$") or "0"
    value = value:sub(-16)
    value = string.rep("0", 16 - #value) .. value
    state.hi = tonumber(value:sub(1, 8), 16) or 0
    state.lo = tonumber(value:sub(9, 16), 16) or 0
  end
  state.width = opts.width or state.width
  apply_mask()
  buf = vim.api.nvim_create_buf(false, true)
  ns = vim.api.nvim_create_namespace("bot_calc")
  local columns, rows = vim.o.columns, vim.o.lines
  win = vim.api.nvim_open_win(buf, true, { relative = "editor", style = "minimal", border = "rounded", width = math.min(82, columns - 4), height = math.min(state.width / 2 + 10, rows - 4), row = math.max(0, math.floor((rows - 16) / 2)), col = math.max(0, math.floor((columns - 82) / 2)) })
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  map("q", "Close inspector", function() vim.api.nvim_win_close(win, true) end)
  map("h", "Move to next bit", function() move(1) end)
  map("l", "Move to previous bit", function() move(-1) end)
  map("<Left>", "Move to previous bit", function() move(-1) end)
  map("<Right>", "Move to next bit", function() move(1) end)
  map("j", "Move down a byte", function() move(8) end)
  map("k", "Move up a byte", function() move(-8) end)
  for _, key in ipairs({ "<Space>", "x", "~" }) do map(key, "Toggle bit", toggle) end
  map("s", "Swap endian view", function() state.little_endian = not state.little_endian; render() end)
  map("y", "Copy hex value", function() vim.fn.setreg("+", as_hex()) end)
  map("d", "Copy decimal value", function() vim.fn.setreg("+", decimal(state.hi, state.lo)) end)
  map("<C-h>", "Shift left", function() shift(true) end)
  map("<C-l>", "Shift right", function() shift(false) end)
  map("r", "Rotate left", function() rotate(true) end)
  map("R", "Rotate right", function() rotate(false) end)
  map("i", "Invert value", function() state.hi, state.lo = bit.bnot(state.hi), bit.bnot(state.lo); apply_mask(); render() end)
  local widths = { ["8"] = 8, ["1"] = 16, ["3"] = 32, ["6"] = 64 }
  for key, width in pairs(widths) do map(key, "Set " .. width .. " bit width", function() state.width = width; apply_mask(); state.cursor = math.min(state.cursor, width - 1); render() end) end
  map("w", "Move to next bit", function() move(1) end)
  map("b", "Move to previous bit", function() move(-1) end)
  render()
end

function M.setup(opts)
  opts = opts or {}
  vim.api.nvim_create_user_command("BotCalc", function(command)
    M.open({ value = command.args ~= "" and command.args or opts.value, width = opts.width })
  end, { nargs = "?", complete = "none", desc = "Open the programmer bit calculator" })
end

return M
