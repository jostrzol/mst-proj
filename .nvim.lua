local null_ls = require("null-ls")
local null_ls_config = require("conf.plugins.null-ls");

table.insert(
  null_ls_config.sources,
  null_ls.builtins.diagnostics.cppcheck.with({
    extra_args = { "--addon=c/misra.json" }
  })
)

---@diagnostic disable-next-line: redundant-parameter
-- null_ls.setup({
--   null_ls.builtins.diagnostics.cppcheck.with({
--     extra_args = { "--addon=misra" }
--   }),
-- });
