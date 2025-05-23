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
					"/home/ogurczak/esp/llvm-project/build/bin/clangd",
					"--query-driver=/home/ogurczak/.espressif/tools/xtensa-esp-elf/esp-14.2.0_20241119/xtensa-esp-elf/bin/xtensa-esp32-elf-gcc*",
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
}
