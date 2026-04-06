package.loaded["luai.prompt.vim_module"] = nil
vim.api.nvim_buf_set_lines(550, 0, -1, false, vim.split(require "luai.prompt.vim_module", "\n"))
