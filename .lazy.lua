---@type LazySpec
return {
	"AstroNvim/astrolsp",
	---@type AstroLSPOpts
	opts = {
		config = {
			tailwindcss = {
				autostart = false,
			},
			clangd = {
				cmd = {
					"/home/ogurczak/.espressif/tools/esp-clang/16.0.1-fe4f10a809/esp-clang/bin/clangd",
					"--query-driver=/home/ogurczak/.espressif/tools/xtensa-esp-elf/esp-14.2.0_20241119/xtensa-esp-elf/bin/xtensa-esp32-elf-gcc",
				},
			},
			rust_analyzer = {
				settings = {
					["rust-analyzer"] = {
						cargo = {
							extraArgs = { "--release" },
							-- targetDir = "target_analyzer",
							allTargets = false,
						},
						server = {
							extraEnv = {
								-- RUSTUP_TOOLCHAIN = "esp",
							},
						},
					},
				},
			},
		},
	},
	{
		"coder/claudecode.nvim",
		---@type ClaudeCodeConfig
		---@diagnostic disable-next-line: missing-fields
		-- opts = {
		-- 	terminal = {
		-- 		snacks_win_opts = {
		-- 			position = "bottom",
		-- 			height = 0.4,
		-- 			width = 1.0,
		-- 			border = "single",
		-- 		},
		-- 	},
		-- },
	},
	{
		"nvim-neo-tree/neo-tree.nvim",
		opts = {
			filesystem = {
				filtered_items = {
					hide_by_pattern = {
						"*/analyze/out/plots/*.pdf",
						"*/analze/notebooks/*_files",
						"*/analze/notebooks/*.html",
					},
				},
			},
		},
		opts_extend = { "filesystem.filtered_items.hide_by_pattern" },
	},
}
