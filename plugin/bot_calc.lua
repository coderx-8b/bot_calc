if vim.g.loaded_bot_calc then return end
vim.g.loaded_bot_calc = true

require("bot_calc").setup()
