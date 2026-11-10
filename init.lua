-- ============================================================================
--  Neovim Super IDE — one file that installs, runs, updates and removes itself
-- ============================================================================
--
--  This file is the whole IDE. Started by Neovim as a configuration, it is
--  the editor; run as a script with `nvim -l init.lua <command>`, it is the
--  installer, the uninstaller and everything in between. How to prepare a
--  machine and install is told in README.md, which travels with this file.
--
--  Design creed
--    * One file, every platform. Neovim is the runtime; the same Lua runs on
--      Linux, macOS and Windows. The only work left outside is what must
--      happen before any Neovim exists: install.sh / install.ps1 add the
--      system packages and fetch the pinned Neovim, then hand over to
--      `nvim -l init.lua install`. They hold no IDE logic and take no part
--      in generations.
--    * Bring your own compiler; the IDE brings everything else. Servers,
--      formatters, parsers and debuggers arrive the first time a language
--      is met, so a machine pays only for the languages it speaks.
--    * Reproducible by construction. The LOCK table below pins Neovim, every
--      plugin and every tool. The same file installs the same IDE anywhere.
--    * A generation is a whole file. Code and versions are only proven
--      together, so history keeps complete copies of this file, never a
--      version table torn from its code. Only :IDEPin makes a generation.
--    * Leave no footprints. Neovim and the IDE live in your user directory,
--      apart from any system Neovim. The configuration found before install
--      is set aside as nvim-orig and comes back exactly on uninstall.
--    * Never escalate privileges behind your back. A missing system package
--      is named, its command shown, and nothing runs without your yes.
--
--  Map of this file
--     0. LOCK ................ pinned versions, written by :IDEPin
--     1. Settings ............ the few knobs worth turning
--     2. Platform ............ where we are and where things live
--     3. Lifecycle ........... install, uninstall, generations (no plugins)
--        ── script mode stops here; the editor starts below ──
--     4. Sandbox ............. private caches and PATH for this Neovim
--     5. Editor options ...... display, editing, indentation, clipboard
--     6. Habits .............. cursor cross, column guides, indentation, ...
--     7. Global keymaps ...... window moves, buffers, search, insert wraps
--     8. Language registry ... ONE table that describes every language
--     9. Provisioning ........ on-demand installers (Mason, runtimes, parsers)
--    10. LSP ................. native vim.lsp, keymaps on attach
--    11. Run & debug ......... <F6>/<F7> runners, DAP on demand
--    12. Plugins ............. lazy.nvim specs
--    13. Dashboard ........... the hexagram start screen
--    14. Commands ............ :IDEDoctor, :IDEUpdate, :IDEPin, :IDEAdd, ...
--
--  Reading the Lua: the Neovim API in one page
--    A handful of Neovim calls appear again and again. Each is explained
--    where it first matters; this is the overview. Full text: :help lua-guide,
--    and :help <name> for any function below.
--
--    vim.opt.X / vim.o.X     an option, like :set X (vim.opt also takes lists)
--    vim.bo[buf].X           a buffer-local option ('filetype', 'expandtab')
--    vim.wo[win].X           a window-local option ('cursorline')
--    vim.g.X / vim.b[buf].X  a global / buffer variable, like g:X / b:X
--    vim.env.X               an environment variable of this process
--    vim.fn.X(...)           any Vimscript function: executable(), expand(), ...
--    vim.cmd.X(...)          any Ex command: vim.cmd.edit(path) is :edit path
--    vim.keymap.set(mode, lhs, rhs, opts)
--                            a key mapping. mode: "n" Normal, "i" Insert,
--                            "x" Visual, "t" Terminal (or a list of them).
--                            rhs: keys, or a Lua function. opts.desc labels it
--                            (which-key shows it); opts.buffer limits it to one
--                            buffer; opts.expr: the function returns the keys.
--    vim.api.nvim_create_user_command(name, fn, opts)
--                            an Ex command such as :IDEDoctor. fn(cmd) gets the
--                            call: cmd.args (the text after the name),
--                            cmd.fargs (that text split on spaces), cmd.bang
--                            (typed with !). opts.nargs: how many arguments —
--                            0 (the default), 1, "?" (0 or 1), "*" (any number);
--                            opts.complete: what <Tab> offers; opts.desc: help.
--    vim.api.nvim_create_autocmd(event, opts)
--                            run opts.callback(ev) whenever an event fires
--                            ("FileType", "VimEnter", "LspAttach", ...). ev.buf
--                            is the buffer, ev.match what matched (for FileType,
--                            the filetype). opts.group: its augroup;
--                            opts.once: fire only the first time.
--    vim.api.nvim_create_augroup(name, { clear = true })
--                            a named set of autocmds; clear = true drops the
--                            old ones first, so loading twice never doubles them.
--    vim.system(cmd, opts, on_exit)
--                            run a program. cmd is a list (no shell, so no
--                            quoting problems). :wait() blocks and returns
--                            { code, stdout, stderr }; with on_exit it returns
--                            at once and calls back when the program ends.
--    vim.schedule(fn), vim.schedule_wrap(fn)
--                            run fn on the main loop as soon as it is free.
--                            Callbacks from vim.system and libuv run in a "fast"
--                            context where most of the API may not be used;
--                            scheduling hops out of it.
--    vim.defer_fn(fn, ms)    run fn once, ms milliseconds from now.
--    vim.wait(ms, cond, step) keep the event loop turning until cond() is true
--                            or ms pass: how headless runs wait for background work.
--    uv (vim.uv)             libuv, the event library under Neovim. uv.fs_stat,
--                            uv.fs_rename, uv.fs_symlink, ...: file-system calls
--                            made directly, never through a shell.
--    vim.fs.*, vim.json.*, vim.iter, vim.tbl_*
--                            plain helpers for paths, JSON and tables.
--    pcall(f, ...)           call f, catching any error: returns ok, then the
--                            result (or the error message).
--    require("x")            load a Lua module, Neovim's own or a plugin's;
--                            wrapped in pcall where the plugin may be missing.
--
--  Authors: Rocky (author) · ChatGPT · Claude
--  License: MIT (see LICENSE) · Copyright (c) 2026 Rocky
-- ============================================================================

-- has("nvim-0.12") is 1 when this Neovim is 0.12 or newer. Older ones get a
-- bare editor (interactive) or exit code 1 (script mode, where _G.arg exists).
if vim.fn.has("nvim-0.12") == 0 then
  local msg = "Super IDE needs Neovim 0.12 or newer (found " .. tostring(vim.version()) .. "). See README.md."
  if _G.arg then io.stderr:write(msg, "\n"); os.exit(1) end
  vim.api.nvim_echo({ { msg .. " Loading a bare editor instead.", "ErrorMsg" } }, true, {})
  return
end

-- ============================================================================
-- 0. LOCK
-- ============================================================================
-- The versions this file was proven with. :IDEPin rewrites the block between
-- the two markers; edit it by hand only if you know why.
-- @@LOCK BEGIN
local LOCK = {
  pinned = "2026-11-06",
  neovim = "v0.12.6",
  plugins = {
    ["LuaSnip"] = { branch = "master", commit = "642b0c595e11608b4c18219e93b88d7637af27bc" },
    ["NeoSolarized.nvim"] = { branch = "master", commit = "3c55ad358c062aa4879950c4f83b4deeac6b72df" },
    ["blink.cmp"] = { branch = "main", commit = "78336bc89ee5365633bcf754d93df01678b5c08f" },
    ["conform.nvim"] = { branch = "master", commit = "016802de402556da54c36bd7359b441266b01cdd" },
    ["friendly-snippets"] = { branch = "main", commit = "b2ea5c41a150ba72fb656eedb4ed0a86d138d945" },
    ["fzf-lua"] = { branch = "main", commit = "11357ee24a9f092b1db503237eb57e2a11e48434" },
    ["gitsigns.nvim"] = { branch = "main", commit = "4bcd99167c265f135886b282baad77afe06206b2" },
    ["indent-blankline.nvim"] = { branch = "master", commit = "f1e186e44d3b7f9ae918008e2c28ce37c6023d2d" },
    ["lazy.nvim"] = { branch = "main", commit = "306a05526ada86a7b30af95c5cc81ffba93fef97" },
    ["lualine.nvim"] = { branch = "master", commit = "221ce6b2d999187044529f49da6554a92f740a96" },
    ["mason.nvim"] = { branch = "main", commit = "2a6940af80375532e5e9e7c1f2fc6319a1b7a69d" },
    ["neo-tree.nvim"] = { branch = "v3.x", commit = "1a14083046d96e88e361d1da00761c40d45012f3" },
    ["neogen"] = { branch = "main", commit = "23e7e9f883d01289ebd90e98025acc860ea26366" },
    ["nui.nvim"] = { branch = "main", commit = "10fc361835c856ba4233ef5ea135b919bf3dce97" },
    ["nvim-autopairs"] = { branch = "master", commit = "3172f40c16563db871a58f20d205c710ad782311" },
    ["nvim-dap"] = { branch = "master", commit = "cfa2d58f4537aca6ca83e2de1a0d9f1491121264" },
    ["nvim-dap-ui"] = { branch = "master", commit = "cc9dd33aade7f20bae414d0cba163bc60d4d4b43" },
    ["nvim-lspconfig"] = { branch = "master", commit = "cc404d425c7752f56b8eaa269107be44d888ea51" },
    ["nvim-nio"] = { branch = "master", commit = "edcc181a875301dd21840189aa2f2f9ad69fc172" },
    ["nvim-surround"] = { branch = "main", commit = "8b47db616ef658b8fc27e61db2896aa2f40134de" },
    ["nvim-treesitter"] = { branch = "main", commit = "610734c5d3e59761d5f79318d120633374537fa5" },
    ["nvim-web-devicons"] = { branch = "master", commit = "ec309a0eaff6ea967e58c275996155ab5c16938d" },
    ["oil.nvim"] = { branch = "master", commit = "d3733d933833a0e59b813ecec99341527adf0c28" },
    ["outline.nvim"] = { branch = "main", commit = "03ce1482222dc2bf1f781559508301f05382936d" },
    ["persistence.nvim"] = { branch = "main", commit = "b20b2a7887bd39c1a356980b45e03250f3dce49c" },
    ["plenary.nvim"] = { branch = "master", commit = "74b06c6c75e4eeb3108ec01852001636d85a932b" },
    ["rainbow-delimiters.nvim"] = { branch = "master", commit = "65734f76783705255d9ede8a6e4692e1572801a5" },
    ["toggleterm.nvim"] = { branch = "main", commit = "50ea089fc548917cc3cc16b46a8211833b9e3c7c" },
    ["vim-fugitive"] = { branch = "master", commit = "3b753cf8c6a4dcde6edee8827d464ba9b8c4a6f0" },
    ["which-key.nvim"] = { branch = "main", commit = "3aab2147e74890957785941f0c1ad87d0a44c15a" },
  },
  tools = {},
  langs = {},
}
-- @@LOCK END

-- ============================================================================
-- 1. Settings
-- ============================================================================
-- The only table you should need to edit. Everything below reads from it.
local SETTINGS = {
  leader          = ",",     -- <leader> in every mapping below
  format_on_save  = true,    -- toggle at runtime with <leader>tf
  debug           = true,    -- DAP support; adapters still download on first <F5>
  auto_install    = true,    -- fetch tooling the first time a language is opened
  python_provider = false,   -- only legacy remote plugins need pynvim
  ui2             = false,   -- Neovim 0.12's experimental message UI (no more "Press ENTER")

  -- Download sources. Point these at mirrors when GitHub or nodejs.org are
  -- slow or unreachable.
  github          = "https://github.com",
  neovim_releases = "https://github.com/neovim/neovim/releases/download",
  node_dist       = "https://nodejs.org/dist",
  adoptium_api    = "https://api.adoptium.net",
}

-- ============================================================================
-- 2. Platform
-- ============================================================================
-- Pure facts and helpers: nothing here writes to disk, because the installer
-- must look around before it is allowed to touch anything.
local uv = vim.uv
local uname = uv.os_uname()

local OS = (uname.sysname == "Darwin" and "mac")
  or (uname.sysname:find("Windows") and "win")
  or "linux"
local ARCH = (uname.machine:find("arm64") or uname.machine:find("aarch64")) and "arm64" or "x64"
local IS_WIN = OS == "win"
local PATH_SEP = IS_WIN and ";" or ":"
local EXE = IS_WIN and ".exe" or ""
local NULL_DEV = IS_WIN and "NUL" or "/dev/null"
local SCRIPT = type(_G.arg) == "table" and _G.arg[0] ~= nil   -- run by `nvim -l`
local HEADLESS = SCRIPT or #vim.api.nvim_list_uis() == 0
local HOME = vim.fs.normalize(uv.os_homedir() or "")

local function exe(name) return vim.fn.executable(name) == 1 end
local function joinpath(...) return vim.fs.joinpath(...) end

-- Neovim's four directories for an application name, computed the way Neovim
-- computes them. The uninstaller runs under a borrowed name, so it cannot
-- simply ask stdpath() for the real ones.
local function nvim_dirs(name)
  local env = vim.env
  if IS_WIN then
    local lad = env.LOCALAPPDATA or joinpath(HOME, "AppData", "Local")
    return {
      config = joinpath(env.XDG_CONFIG_HOME or lad, name),
      data   = joinpath(env.XDG_DATA_HOME or lad, name .. "-data"),
      state  = joinpath(env.XDG_STATE_HOME or lad, name .. "-data"),
      cache  = joinpath(env.XDG_CACHE_HOME or env.TEMP or lad, name),
    }
  end
  return {
    config = joinpath(env.XDG_CONFIG_HOME or joinpath(HOME, ".config"), name),
    data   = joinpath(env.XDG_DATA_HOME or joinpath(HOME, ".local", "share"), name),
    state  = joinpath(env.XDG_STATE_HOME or joinpath(HOME, ".local", "state"), name),
    cache  = joinpath(env.XDG_CACHE_HOME or joinpath(HOME, ".cache"), name),
  }
end

-- DIR and FILE are filled in by relocate(), which the uninstaller calls again
-- to point every helper at the real application name.
local DIR, FILE = {}, {}
local BIN_DIR = joinpath(HOME, ".local", "bin")
-- Windows: winget's LLVM package installs clang here but does not add it to
-- PATH. The sandbox (section 4) adds it for this Neovim only; the installer's
-- compiler check looks here too. install.ps1 uses the same path.
local LLVM_BIN = IS_WIN and joinpath(vim.env.ProgramFiles or "C:/Program Files", "LLVM", "bin") or nil
local ENTRY      -- the command entry: a link on Unix, a user PATH entry on Windows

local function relocate(name)
  local base = nvim_dirs(name)
  if not SCRIPT then   -- inside the editor Neovim's own answer is authoritative
    for k in pairs(base) do base[k] = vim.fn.stdpath(k) end
  end
  for k in pairs(DIR) do DIR[k] = nil end
  for k, v in pairs(base) do DIR[k] = vim.fs.normalize(v) end
  DIR.home     = joinpath(DIR.data, "super-ide")
  DIR.bin      = joinpath(DIR.home, "bin")         -- portable rg / fd / fzf
  DIR.runtimes = joinpath(DIR.home, "runtimes")    -- portable Node.js / JDK
  DIR.records  = joinpath(DIR.home, "records")     -- what we changed, for a clean uninstall
  DIR.gens     = joinpath(DIR.home, "generations") -- every pinned init.lua, one file each
  DIR.rejected = joinpath(DIR.home, "rejected")    -- unpinned edits set aside by a switch
  DIR.boot     = joinpath(DIR.home, "bootstrap")   -- install.sh / install.ps1, for :IDEExport
  DIR.clangd   = joinpath(DIR.cache, "clangd-index")
  DIR.xdg      = joinpath(DIR.cache, "xdg")        -- private XDG cache for clangd
  DIR.dl       = joinpath(DIR.cache, "downloads")
  DIR.opt      = IS_WIN and joinpath(vim.env.LOCALAPPDATA or joinpath(HOME, "AppData", "Local"), "super-ide")
                         or joinpath(HOME, ".local", "opt", "super-ide")   -- our own Neovim builds
  DIR.trash    = joinpath(vim.fs.dirname(DIR.data), ".super-ide-trash")

  FILE.init      = joinpath(DIR.config, "init.lua")
  FILE.marker    = joinpath(DIR.config, ".super-ide")
  FILE.lockfile  = joinpath(DIR.home, "lazy-lock.json")   -- written from LOCK.plugins
  FILE.manifest  = joinpath(DIR.records, "install.tsv")
  FILE.history   = joinpath(DIR.records, "history.tsv")
  FILE.candidate = joinpath(DIR.records, "candidate.json")
  FILE.pending   = joinpath(DIR.records, "pending.json")
  ENTRY = IS_WIN and joinpath(DIR.opt, "current", "bin") or joinpath(BIN_DIR, "nvim")
end
local APPNAME = vim.env.NVIM_APPNAME or "nvim"
relocate(APPNAME)

-- Append a line to a record file (one record per line, tab-separated fields).
local function record(file, ...)
  vim.fn.mkdir(DIR.records, "p")
  local f = io.open(joinpath(DIR.records, file), "a")
  if f then
    f:write(table.concat({ ... }, "\t"), "\n")
    f:close()
  end
end

local function read_records(file)
  local out = {}
  local f = io.open(joinpath(DIR.records, file))
  if not f then return out end
  for line in f:lines() do
    if line ~= "" then out[#out + 1] = vim.split(line, "\t", { plain = true }) end
  end
  f:close()
  return out
end

local function notify(msg, level)
  if SCRIPT then
    io.write((level or 0) >= vim.log.levels.WARN and "!!  " or "==> ", msg, "\n")
    return
  end
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Super IDE" })
  end)
end

-- ============================================================================
-- 3. Lifecycle — install, uninstall and generations
-- ============================================================================
-- Built only on Neovim's own modules (vim.uv, vim.system, vim.fs, vim.json),
-- so the same code runs under `nvim -l` (no plugins, no UI) and behind the
-- :IDE* commands. Everything lives in the LC table and a do-block, which
-- keeps the main chunk well under Lua's limit of 200 local variables.
local LC = { yes = false, started = os.time() }

do
  -- Messages ------------------------------------------------------------------
  local function log_line(line)
    if not LC.log then return end
    local f = io.open(LC.log, "a")
    if f then f:write(line, "\n"); f:close() end
  end
  function LC.say(msg)
    log_line("==> " .. msg)
    -- Script mode has no UI: plain stdout, flushed so the line shows at once.
    if SCRIPT then io.write("==> ", msg, "\n"); io.flush(); return end
    -- In the editor these steps block (downloads), so show them right away.
    vim.api.nvim_echo({ { msg } }, true, {})
    if not HEADLESS then vim.cmd.redraw() end
  end
  function LC.warn(msg)
    log_line("!!  " .. msg)
    if SCRIPT then io.write("!!  ", msg, "\n"); io.flush() else notify(msg, vim.log.levels.WARN) end
  end
  -- A failure stops the operation; script mode prints it and exits 1, the
  -- editor shows it as an error. error(msg, 0) keeps file:line out of it.
  local function fail(msg) error(msg, 0) end
  LC.fail = fail

  -- One line from stdin; nil at end of input. From a terminal it is read
  -- through the event loop, which keeps running while we wait, so Ctrl+C at a
  -- question still reaches the installer's rollback ("Cancel and roll back").
  -- io.read would block in C until Enter, and Ctrl+C would only count then.
  -- (libuv opens its own handle on the terminal, so the blocking mode of
  -- stdin, which programs started later inherit, stays as it was.)
  local function read_line()
    if uv.guess_handle(0) ~= "tty" then return io.read("*l") end
    local tty = uv.new_tty(0, true)
    local buf, line, eof = "", nil, false
    tty:read_start(function(_, data)
      if not data then eof = true; return end
      buf = buf .. data
      line = buf:match("^(.-)\r?\n")
    end)
    vim.wait(24 * 3600 * 1000, function() return line ~= nil or eof end, 50)
    tty:read_stop()
    tty:close()
    return line
  end

  -- Ask a yes/no question. --yes takes the default; the editor uses a dialog.
  function LC.ask(question, default_yes)
    if LC.yes then return default_yes end
    if not SCRIPT then
      return vim.fn.confirm(question, "&Yes\n&No", default_yes and 1 or 2) == 1
    end
    io.write(question, default_yes and " [Y/n] " or " [y/N] ")
    io.flush()
    local reply = read_line()
    if reply == nil or vim.trim(reply) == "" then return default_yes end
    return reply:match("^%s*[yY]") ~= nil
  end

  -- Files -------------------------------------------------------------------------
  local function lexists(p) return uv.fs_lstat(p) ~= nil end
  local function is_dir(p) local st = uv.fs_stat(p); return st ~= nil and st.type == "directory" end
  local function is_link(p) local st = uv.fs_lstat(p); return st ~= nil and st.type == "link" end
  local function norm(s) return (tostring(s or ""):gsub("\r\n", "\n")) end
  local function read_file(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
  end
  local function write_file(p, s)
    vim.fn.mkdir(vim.fs.dirname(p), "p")
    local f = io.open(p, "wb")
    if not f then fail("cannot write " .. p) end
    f:write(s)
    f:close()
  end
  -- Replace a file in one step: a crash halfway leaves the old file intact.
  local function write_atomic(p, s)
    local tmp = p .. ".tmp"
    write_file(tmp, s)
    -- A rename within one directory is atomic: readers see the old file or
    -- the new one, never half of each. libuv calls return nil, err on failure.
    local ok, err = uv.fs_rename(tmp, p)
    if not ok then fail("cannot replace " .. p .. ": " .. tostring(err)) end
  end
  -- delete(p, "rf"): recursive and forced, like rm -rf; never follows links.
  local function rm(p) if lexists(p) then vim.fn.delete(p, "rf") end end
  local function mv(a, b)
    local ok, err = uv.fs_rename(a, b)
    if not ok then fail(("cannot move %s to %s: %s"):format(a, b, tostring(err))) end
  end
  local function same_path(a, b)
    a, b = vim.fs.normalize(a or ""), vim.fs.normalize(b or "")
    if IS_WIN then a, b = a:lower(), b:lower() end
    return a == b
  end
  -- A symlink on Unix, a directory junction on Windows (no admin rights needed).
  local function make_link(target, link)
    local ok, err = uv.fs_symlink(target, link, { dir = true, junction = true })
    if not ok then fail(("cannot link %s -> %s: %s"):format(link, target, tostring(err))) end
  end
  local function remove_link(p)
    if not is_link(p) then return end
    -- A Windows junction is removed like an empty directory (rmdir), a Unix
    -- symlink like a file (unlink). Neither touches what the link points to.
    if not (IS_WIN and uv.fs_rmdir(p)) then uv.fs_unlink(p) end
  end
  local function link_points_to(link, target)
    return is_link(link) and same_path(uv.fs_readlink(link), target)
  end
  local function json_read(p)
    local s = read_file(p)
    if not s then return nil end
    local ok, t = pcall(vim.json.decode, s)
    return ok and t or nil
  end
  local function json_write(p, t) write_file(p, vim.json.encode(t)) end
  -- A whole directory tree, for the uninstaller's private copy of Neovim.
  local function copy_tree(src, dst)
    vim.fn.mkdir(dst, "p")
    for name, kind in vim.fs.dir(src) do
      local a, b = joinpath(src, name), joinpath(dst, name)
      if kind == "directory" then copy_tree(a, b) else uv.fs_copyfile(a, b) end
    end
  end

  LC.lexists, LC.is_dir, LC.norm, LC.read_file, LC.write_file = lexists, is_dir, norm, read_file, write_file
  LC.write_atomic, LC.rm, LC.json_read, LC.json_write, LC.same_path = write_atomic, rm, json_read, json_write, same_path

  -- Processes ---------------------------------------------------------------------
  -- The full environment plus a few overrides, as uv.spawn wants it.
  local function env_with(extra)
    -- environ() returns this process's environment as a { NAME = value } table.
    local env = vim.fn.environ()
    for k, v in pairs(extra or {}) do env[k] = v end
    local list = {}
    for k, v in pairs(env) do list[#list + 1] = k .. "=" .. v end
    return list
  end
  -- Run a program on this terminal (it can prompt, sudo can ask for a
  -- password) and wait for it. Returns the exit code.
  local function run_tty(cmd, args, extra_env)
    local done, code = false, -1
    -- uv.spawn starts the program directly. stdio = { 0, 1, 2 } hands it
    -- our own stdin/stdout/stderr, i.e. the terminal (vim.system would capture
    -- them). The callback receives the exit code; vim.wait turns the event
    -- loop until it has arrived.
    local handle = uv.spawn(cmd, { args = args, stdio = { 0, 1, 2 }, env = extra_env and env_with(extra_env) or nil },
      function(c) code, done = c, true end)
    if not handle then return -1 end
    LC.child = handle   -- an install rollback stops it first (see "Cancel and roll back")
    vim.wait(24 * 3600 * 1000, function() return done end, 100)
    LC.child = nil
    handle:close()
    return code
  end
  LC.run_tty = run_tty

  -- Run a program out of reach of Ctrl+C and wait for it, saying every
  -- `every` seconds how long it has taken so far. detached = true gives it a
  -- session of its own (Unix) or no console (Windows), so the terminal's
  -- Ctrl+C does not reach it; its output is dropped, as it may have no
  -- terminal to write to. For work that must not be cut short (a rollback).
  local function run_shielded(cmd, args, every, label)
    local done, code = false, -1
    local handle = uv.spawn(cmd, { args = args, detached = true }, function(c) code, done = c, true end)
    if not handle then return -1 end
    local start = uv.now()   -- milliseconds, from the event loop's clock
    local shown = 0
    while not vim.wait(1000, function() return done end, 100) do
      local secs = math.floor((uv.now() - start) / 1000)
      if secs - shown >= every then
        shown = secs
        LC.say(("%s (%d:%02d so far)"):format(label, math.floor(secs / 60), secs % 60))
      end
    end
    handle:close()
    return code
  end

  -- History -------------------------------------------------------------------------
  function LC.history(action, detail)
    record("history.tsv", os.date("%Y-%m-%d %H:%M"), action, detail or "")
  end

  -- Versions ------------------------------------------------------------------------
  local function parse_tag(tag)
    local a, b, c = tostring(tag or ""):match("^v?(%d+)%.(%d+)%.(%d+)$")
    if a then return { tonumber(a), tonumber(b), tonumber(c) } end
  end
  function LC.running_tag()
    local v = vim.version()
    return ("v%d.%d.%d"):format(v.major, v.minor, v.patch)
  end
  LC.parse_tag = parse_tag

  -- Neovim builds under DIR.opt -------------------------------------------------------
  local function nvim_asset()
    if OS == "linux" then return ARCH == "arm64" and "nvim-linux-arm64.tar.gz" or "nvim-linux-x86_64.tar.gz" end
    if OS == "mac" then return ARCH == "arm64" and "nvim-macos-arm64.tar.gz" or "nvim-macos-x86_64.tar.gz" end
    return ARCH == "arm64" and "nvim-win-arm64.zip" or "nvim-win64.zip"
  end
  local function build_dir(tag) return joinpath(DIR.opt, "nvim-" .. tag) end
  local function build_exe(dir) return joinpath(dir, "bin", "nvim" .. EXE) end
  local function current_link() return joinpath(DIR.opt, "current") end
  function LC.current_exe() return build_exe(current_link()) end
  LC.build_dir, LC.build_exe = build_dir, build_exe

  -- Does this binary run, and is it the version we expect?
  local function build_works(bin, tag)
    if vim.fn.executable(bin) ~= 1 then return false end
    local r = vim.system({ bin, "--clean", "--headless", "--version" },
      { text = true, env = { NVIM_APPNAME = "super-ide-probe" } }):wait()
    local v = (r.stdout or ""):match("NVIM (v%d+%.%d+%.%d+)")
    rm(nvim_dirs("super-ide-probe").state)   -- every Neovim start leaves an empty log directory
    return r.code == 0 and (tag == nil or v == tag)
  end

  -- Download a release into DIR.opt/nvim-<tag>. It is unpacked beside the
  -- final place and tested there first, so a failed download changes nothing.
  -- LC.archive (install --archive FILE) is the release archive install.sh /
  -- install.ps1 already downloaded to start this installer: it is used instead
  -- of a second download, and left in place, because the script owns it. A
  -- wrong archive is still caught: the version check below rejects it.
  function LC.fetch_neovim(tag)
    local dest = build_dir(tag)
    if build_works(build_exe(dest), tag) then return dest end
    local asset = nvim_asset()
    local url = ("%s/%s/%s"):format(SETTINGS.neovim_releases, tag, asset)
    local tmp, file = joinpath(DIR.opt, ".incoming-" .. tag), joinpath(DIR.opt, asset)
    local own = not (LC.archive and uv.fs_stat(LC.archive))   -- false: unpack the script's archive
    rm(tmp)
    vim.fn.mkdir(tmp, "p")
    if own then
      LC.say(("Downloading Neovim %s (%s) …"):format(tag, asset))
      local r = vim.system({ "curl", "-fsSL", "--retry", "2", "-o", file, url }, { text = true }):wait()
      if r.code ~= 0 then
        rm(tmp); os.remove(file)
        fail("download failed: " .. url .. "\n    " .. vim.trim(r.stderr or ""))
      end
    else
      file = LC.archive
      LC.say(("Unpacking Neovim %s from %s …"):format(tag, file))
    end
    local r = vim.system({ "tar", "-xf", file, "-C", tmp, "--strip-components=1" }, { text = true }):wait()
    if own then os.remove(file) end
    if r.code ~= 0 then rm(tmp); fail("unpacking " .. asset .. " failed: " .. vim.trim(r.stderr or "")) end
    if OS == "mac" then vim.system({ "xattr", "-cr", tmp }):wait() end   -- Gatekeeper's quarantine flag
    if not build_works(build_exe(tmp), tag) then rm(tmp); fail("the downloaded Neovim " .. tag .. " does not run here") end
    rm(dest)
    mv(tmp, dest)
    return dest
  end

  -- Point DIR.opt/current at a build. The command entry follows the link,
  -- so switching versions never touches PATH again.
  function LC.set_current(tag)
    local link = current_link()
    if lexists(link) and not is_link(link) then fail(link .. " exists and is not a link") end
    remove_link(link)
    make_link(build_dir(tag), link)
  end
  function LC.current_tag()
    local target = uv.fs_readlink(current_link())
    return target and vim.fs.basename(vim.fs.normalize(target)):match("^nvim%-(v[%d.]+)$") or nil
  end

  -- Keep one generation on disk: remove every build except the ones named.
  function LC.prune_builds(keep)
    if not is_dir(DIR.opt) then return end
    for name in vim.fs.dir(DIR.opt) do
      local tag = name:match("^nvim%-(v[%d.]+)$")
      if (tag and not keep[tag]) or name:match("^%.incoming") then pcall(rm, joinpath(DIR.opt, name)) end
    end
  end

  -- Release tags >= 0.12, newest last, read from git (no API rate limit).
  function LC.release_tags()
    local r = vim.system({ "git", "ls-remote", "--tags", "--refs", SETTINGS.github .. "/neovim/neovim" }, { text = true }):wait()
    local tags = {}
    for tag in (r.stdout or ""):gmatch("refs/tags/(v%d+%.%d+%.%d+)\n") do
      local v = parse_tag(tag)
      if v[1] > 0 or v[2] >= 12 then tags[#tags + 1] = tag end
    end
    table.sort(tags, function(x, y)
      local a, b = parse_tag(x), parse_tag(y)
      for i = 1, 3 do if a[i] ~= b[i] then return a[i] < b[i] end end
      return false
    end)
    return tags
  end

  -- The LOCK block ---------------------------------------------------------------------
  local BEGIN, END = "\n-- @@LOCK BEGIN\n", "\n-- @@LOCK END"
  local function lock_span(text)
    local a = text:find(BEGIN, 1, true)
    local b = a and text:find(END, a + #BEGIN - 1, true)
    if a and b then return a + #BEGIN, b end
  end
  -- Read the LOCK of any init.lua without running the rest of it.
  function LC.lock_from_text(text)
    text = norm(text)
    local s, e = lock_span(text)
    if not s then return nil end
    -- The LOCK block is Lua (`local LOCK = { ... }`), so Lua reads it:
    -- loadstring compiles the text to a function without running it, and
    -- setfenv(chunk, {}) gives that function an empty global table, so the
    -- block can build a table but cannot call anything (no os, no io, no vim).
    local chunk = loadstring(text:sub(s, e - 1) .. "\nreturn LOCK", "=LOCK")
    if not chunk then return nil end
    setfenv(chunk, {})
    local ok, t = pcall(chunk)
    return ok and type(t) == "table" and t or nil
  end
  -- Deterministic text: sorted keys, one entry per line, so a diff between
  -- two generations shows exactly what moved.
  function LC.lock_render(lk)
    local L = { "local LOCK = {", ("  pinned = %q,"):format(lk.pinned or ""), ("  neovim = %q,"):format(lk.neovim) }
    local function block(name, tbl, fmt)
      local keys = vim.tbl_keys(tbl or {})
      table.sort(keys)
      if #keys == 0 then L[#L + 1] = "  " .. name .. " = {},"; return end
      L[#L + 1] = "  " .. name .. " = {"
      for _, k in ipairs(keys) do L[#L + 1] = fmt(k, tbl[k]) end
      L[#L + 1] = "  },"
    end
    block("plugins", lk.plugins, function(k, p)
      return ("    [%q] = { branch = %q, commit = %q },"):format(k, p.branch, p.commit)
    end)
    block("tools", lk.tools, function(k, v) return ("    [%q] = %q,"):format(k, v) end)
    local langs = vim.deepcopy(lk.langs or {})
    table.sort(langs)
    L[#L + 1] = #langs == 0 and "  langs = {},"
      or ("  langs = { %s },"):format(table.concat(vim.tbl_map(function(s) return ("%q"):format(s) end, langs), ", "))
    L[#L + 1] = "}"
    return table.concat(L, "\n")
  end
  function LC.lock_replace(text, lk)
    text = norm(text)
    local s, e = lock_span(text)
    if not s then fail("this init.lua has no @@LOCK block") end
    return text:sub(1, s - 1) .. LC.lock_render(lk) .. text:sub(e)
  end

  -- Generations -----------------------------------------------------------------------
  -- One complete init.lua per pinned state, named by time and Neovim version.
  -- records/generation names the one in effect.
  local function gen_path(name) return joinpath(DIR.gens, name) end
  function LC.gen_list()
    local t = {}
    if is_dir(DIR.gens) then
      for name, kind in vim.fs.dir(DIR.gens) do
        if kind == "file" and name:match("%.lua$") then t[#t + 1] = name end
      end
    end
    table.sort(t)
    return t
  end
  function LC.gen_text(name) local s = read_file(gen_path(name)); return s and norm(s) or nil end
  function LC.gen_current()
    local name = vim.trim(read_file(joinpath(DIR.records, "generation")) or "")
    if name ~= "" and lexists(gen_path(name)) then return name end
    local all = LC.gen_list()
    return all[#all]
  end
  local function gen_find(text)
    for _, name in ipairs(LC.gen_list()) do
      if LC.gen_text(name) == text then return name end
    end
  end
  -- Store a text as a generation (or find the identical one) and make it current.
  function LC.gen_add(text)
    text = norm(text)
    local name = gen_find(text)
    if not name then
      local lk = LC.lock_from_text(text) or {}
      name = ("%s_nvim-%s.lua"):format(os.date("%Y%m%d-%H%M%S"), lk.neovim or "unknown")
      write_file(gen_path(name), text)
    end
    write_file(joinpath(DIR.records, "generation"), name .. "\n")
    return name
  end
  LC.gen_find, LC.gen_path = gen_find, gen_path

  -- Set an unpinned init.lua aside before replacing it.
  local function keep_rejected(text)
    if not text or gen_find(norm(text)) then return end
    local p = joinpath(DIR.rejected, "init.lua." .. os.date("%Y%m%d-%H%M%S"))
    write_file(p, text)
    LC.warn("Your unpinned init.lua was set aside as " .. p)
  end

  -- Make a stored generation the live one: its Neovim, its init.lua, its
  -- plugin lock. Plugins, tools and parsers are then brought in line by
  -- :IDESync, which must run under the new Neovim and the new file.
  function LC.switch(name)
    local text = LC.gen_text(name) or fail("no such generation: " .. tostring(name))
    local lk = LC.lock_from_text(text) or fail(name .. " has no readable LOCK")
    keep_rejected(read_file(FILE.init))
    local before = LC.current_tag()
    LC.fetch_neovim(lk.neovim)
    LC.set_current(lk.neovim)
    write_atomic(FILE.init, text)
    json_write(FILE.lockfile, lk.plugins)
    write_file(joinpath(DIR.records, "generation"), name .. "\n")
    os.remove(FILE.candidate)
    if before ~= lk.neovim then   -- parsers are compiled against one Neovim's ABI
      local p = json_read(FILE.pending) or {}
      p.parsers = true
      json_write(FILE.pending, p)
    end
    -- The Neovim running this code keeps its build until the next pin or
    -- switch: deleting a live runtime pulls the floor from under it.
    LC.prune_builds({ [lk.neovim] = true, [LC.running_tag()] = true })
    return lk
  end

  -- Run :IDESync with the live Neovim on this terminal (installer, import).
  -- shielded: as part of a rollback, out of reach of Ctrl+C, with a line
  -- every 15 seconds instead of the sync's own output, so a long wait never
  -- looks like a hang.
  function LC.sync_here(shielded)
    local args = { "--headless", "+IDESync", "+qa" }
    if shielded then
      LC.say("Restoring the previous generation's plugins, tools and parsers. This can take a few")
      LC.say("minutes; please wait. Ctrl+C is ignored until it is done.")
      if run_shielded(LC.current_exe(), args, 15, "Still restoring …") ~= 0 then
        LC.warn("The restore reported problems; start nvim and run :IDESync.")
      end
      return
    end
    LC.say("Bringing plugins, tools and parsers in line with the LOCK (first time: a few minutes) …")
    local code = run_tty(LC.current_exe(), args)
    io.write("\n")
    if code ~= 0 then LC.warn("Sync reported problems; start nvim and run :IDEDoctor.") end
  end

  -- System prerequisites (installer) ------------------------------------------------------
  local function have_cc()
    return exe("cc") or exe("gcc") or exe("clang") or exe("cl")
      or (LLVM_BIN ~= nil and exe(joinpath(LLVM_BIN, "clang.exe")))   -- winget's LLVM, off PATH
  end
  local function python() return exe("python3") and "python3" or (exe("python") and "python") or nil end
  local function have_venv()
    local py = python()
    return py ~= nil and vim.system({ py, "-c", "import ensurepip, venv" }):wait().code == 0
  end

  local function check_system(pending)
    local items = {
      { "git", function() return exe("git") end, true, apt = "git", win = "Git.Git", mac = true },
      { "curl", function() return exe("curl") end, true, apt = "curl" },
      { "tar", function() return exe("tar") end, true, apt = "tar" },
      { "unzip", function() return IS_WIN or exe("unzip") end, false, apt = "unzip" },
      { "a C compiler", have_cc, false, apt = "build-essential", win = "LLVM.LLVM", mac = true },
      { "python3 with venv", have_venv, false, apt = python() and "python3-venv" or "python3 python3-venv",
        win = "Python.Python.3.12" },
    }
    if OS == "linux" and vim.env.WAYLAND_DISPLAY and not exe("wl-copy") then
      items[#items + 1] = { "wl-clipboard", function() return exe("wl-copy") end, false, apt = "wl-clipboard" }
    elseif OS == "linux" and vim.env.DISPLAY and not (exe("xclip") or exe("xsel")) then
      items[#items + 1] = { "xclip", function() return exe("xclip") or exe("xsel") end, false, apt = "xclip" }
    end
    local missing = {}
    for _, it in ipairs(items) do if not it[2]() then missing[#missing + 1] = it end end
    if #missing == 0 then return end
    LC.say("Missing: " .. table.concat(vim.tbl_map(function(it) return it[1] end, missing), ", "))

    if OS == "linux" and exe("apt-get") then
      local pkgs = table.concat(vim.tbl_map(function(it) return it.apt end, missing), " ")
      local sudo = (uv.getuid and uv.getuid() == 0) and "" or "sudo "
      local cmd = ("%sapt-get -o DPkg::Lock::Timeout=600 update && %sapt-get -o DPkg::Lock::Timeout=600 install -y %s")
        :format(sudo, sudo, pkgs)
      LC.say("Proposed: " .. cmd)
      if LC.ask("Run it now?", true) then
        os.execute(cmd)
        for _, it in ipairs(missing) do
          if it[2]() then pending[#pending + 1] = { "system-packages.tsv", OS, it.apt, cmd } end
        end
      end
    elseif OS == "mac" then
      if vim.iter(missing):any(function(it) return it.mac end) then
        LC.say("Starting Apple's installer for git and the compiler (xcode-select --install).")
        os.execute("xcode-select --install")
        fail("Finish the Command Line Tools installation, then run this command again.")
      end
    elseif IS_WIN and exe("winget") then
      for _, it in ipairs(missing) do
        if it.win and LC.ask(("Install %s with winget (%s)?"):format(it[1], it.win), true) then
          local cmd = "winget install -e --id " .. it.win
          if os.execute(cmd) == 0 then pending[#pending + 1] = { "system-packages.tsv", OS, it.win, cmd } end
        end
      end
    end

    local still = {}
    for _, it in ipairs(missing) do
      if not it[2]() then
        still[#still + 1] = it[1]
        if it[3] then
          fail(("%s is required. Install it (see README.md, section 2)%s, then run this again.")
            :format(it[1], IS_WIN and " and open a new terminal" or ""))
        end
      end
    end
    if #still > 0 then LC.warn("Continuing without: " .. table.concat(still, ", ") .. " (README.md explains what each is for).") end
  end

  -- The `nvim` command -------------------------------------------------------------------
  local function ps(cmd)
    return vim.system({ "powershell", "-NoProfile", "-NonInteractive", "-Command", cmd }, { text = true }):wait()
  end
  local function win_path(scope) return vim.trim(ps(("[Environment]::GetEnvironmentVariable('Path','%s')"):format(scope)).stdout or "") end
  local function win_path_set(value)
    ps(("[Environment]::SetEnvironmentVariable('Path','%s','User')"):format((value:gsub("'", "''"))))
  end
  local ZPROFILE = joinpath(HOME, ".zprofile")
  local ZLINE = 'export PATH="$HOME/.local/bin:$PATH"   # added by Neovim Super IDE'

  -- The first `nvim` on a PATH string that is not ours.
  local function shadowing(path_string, ours_dir)
    for d in vim.gsplit(path_string or "", PATH_SEP, { plain = true }) do
      if d ~= "" then
        if same_path(d, ours_dir) then return nil end
        local cand = joinpath(d, "nvim" .. EXE)
        if vim.fn.executable(cand) == 1 then return cand end
      end
    end
  end

  local function install_entry(pending)
    if IS_WIN then
      local entry = ENTRY:gsub("/", "\\")
      local user = win_path("User")
      if not vim.iter(vim.split(user, ";", { plain = true })):any(function(d) return same_path(d, entry) end) then
        win_path_set(entry .. (user ~= "" and (";" .. user) or ""))
        pending[#pending + 1] = { "install.tsv", "user-path", entry }
      end
      local other = shadowing(win_path("Machine"), entry)
      if other then
        LC.warn(("%s comes first on the system PATH, so `nvim` would start it instead of Super IDE."):format(other))
        -- Windows searches the system PATH before the user PATH, and changing
        -- the system PATH needs administrator rights, so only explain.
        LC.warn("If you do not need that Neovim, remove it (winget installs it as Neovim.Neovim) and open a new terminal;")
        LC.warn("otherwise start Super IDE by its full path: " .. joinpath(ENTRY, "nvim.exe"))
      else
        LC.say("Open a new terminal so the updated PATH takes effect.")
      end
      return
    end
    if not lexists(ENTRY) then
      vim.fn.mkdir(BIN_DIR, "p")
      make_link(joinpath(DIR.opt, "current", "bin", "nvim"), ENTRY)
      pending[#pending + 1] = { "install.tsv", "entry", ENTRY }
    end
    local on_path = vim.iter(vim.split(vim.env.PATH or "", ":", { plain = true }))
      :any(function(d) return same_path(d, BIN_DIR) end)
    if OS == "mac" and not on_path and not (read_file(ZPROFILE) or ""):find(ZLINE, 1, true) then
      if LC.ask("~/.local/bin is not on your PATH. Add it in ~/.zprofile (removed again on uninstall)?", true) then
        local existed = lexists(ZPROFILE)
        local f = assert(io.open(ZPROFILE, "a"))
        f:write("\n", ZLINE, "\n")
        f:close()
        pending[#pending + 1] = { "install.tsv", "zprofile-line", ZLINE }
        if not existed then pending[#pending + 1] = { "install.tsv", "zprofile-created", ZPROFILE } end
        on_path = true
      end
    end
    local other = shadowing(vim.env.PATH, BIN_DIR)
    if not on_path then
      LC.say("~/.local/bin is not on PATH yet. Log out and back in (Ubuntu's ~/.profile adds it), or start " .. ENTRY)
    elseif other then
      LC.warn(other .. " comes before ~/.local/bin on PATH; reorder PATH or start " .. ENTRY)
    else
      LC.say("Open a new terminal (or run `hash -r`) so `nvim` starts Super IDE.")
    end
  end

  local function undo_entry(M)
    if IS_WIN then
      for _, entry in ipairs(M["user-path"] or {}) do
        local keep = vim.tbl_filter(function(d) return d ~= "" and not same_path(d, entry) end,
          vim.split(win_path("User"), ";", { plain = true }))
        win_path_set(table.concat(keep, ";"))
      end
      return
    end
    for _, entry in ipairs(M.entry or {}) do
      if link_points_to(entry, joinpath(DIR.opt, "current", "bin", "nvim")) then os.remove(entry) end
    end
    for _, line in ipairs(M["zprofile-line"] or {}) do
      local text = read_file(ZPROFILE)
      if text then
        local kept = vim.tbl_filter(function(l) return l ~= line end, vim.split(text, "\n", { plain = true }))
        local out = (table.concat(kept, "\n"):gsub("\n\n+$", "\n"))
        if M["zprofile-created"] and vim.trim(out) == "" then os.remove(ZPROFILE) else write_file(ZPROFILE, out) end
      end
    end
  end

  -- Put git's core.editor back as the install found it ("<unset>": it had none),
  -- and drop a ~/.gitconfig the install created if nothing else is in it.
  local function undo_git(M)
    local prev = (M["git-editor"] or {})[1]
    if not (prev and exe("git")) then return end
    if prev == "<unset>" then
      vim.system({ "git", "config", "--global", "--unset", "core.editor" }):wait()
    else
      vim.system({ "git", "config", "--global", "core.editor", prev }):wait()
    end
    local gc = (M["gitconfig-created"] or {})[1]
    local st = gc and uv.fs_stat(gc)
    if st and st.size == 0 then os.remove(gc) end
  end

  -- Manifest ------------------------------------------------------------------------------
  -- install.tsv rows (kind, value) as { kind = { value, ... } }. The rows
  -- come from the file, or (rows given) from an install still in progress.
  local function manifest(rows)
    local M = {}
    if rows then
      for _, r in ipairs(rows) do
        if r[1] == "install.tsv" then M[r[2]] = M[r[2]] or {}; table.insert(M[r[2]], r[3]) end
      end
      return M
    end
    for _, r in ipairs(read_records("install.tsv")) do
      M[r[1]] = M[r[1]] or {}
      table.insert(M[r[1]], r[2])
    end
    return M
  end
  -- When a file or directory came into being, from fs_stat: its birth time
  -- where the file system records one, else its last status change.
  local function born(st) return (st.birthtime and st.birthtime.sec > 0) and st.birthtime.sec or st.ctime.sec end

  -- Every Neovim start, this installer's included, creates <state>/nvim.log.
  -- A state directory holding nothing else is ours, not the user's.
  local function only_a_log(dir)
    if not is_dir(dir) then return false end
    for name in vim.fs.dir(dir) do if name ~= "nvim.log" then return false end end
    return true
  end
  -- Parents that did not exist before this run (or were made by its own start):
  -- removed again, when empty, on uninstall.
  local function new_parents()
    if IS_WIN then return {} end
    local list = {}
    -- Only ~/.local and ~/.local/state can have been made by this Neovim's own
    -- start (its log); for those, a birth within the last seconds counts.
    local by_log = { [joinpath(HOME, ".local")] = true, [vim.fs.dirname(DIR.state)] = true }
    for _, d in ipairs({ joinpath(HOME, ".config"), joinpath(HOME, ".local"), joinpath(HOME, ".local", "share"),
      vim.fs.dirname(DIR.state), joinpath(HOME, ".cache"), BIN_DIR, joinpath(HOME, ".local", "opt"), DIR.opt }) do
      local st = uv.fs_stat(d)
      if not st or (by_log[d] and born(st) >= LC.started - 5) then list[#list + 1] = d end
    end
    return list
  end
  local function roots()   -- the directories Neovim owns, without duplicates (Windows shares data/state)
    local seen, out = {}, {}
    for _, k in ipairs({ "config", "data", "state", "cache" }) do
      if not seen[DIR[k]] then seen[DIR[k]] = true; out[#out + 1] = DIR[k] end
    end
    return out
  end

  -- The bootstrap scripts that came with this file (install.sh, install.ps1)
  -- are kept, so :IDEExport can hand a machine without Neovim everything it
  -- needs. Not part of any generation: a later install simply replaces them.
  -- A file installed without them (plain `nvim -l`) keeps the old copies.
  LC.SCRIPTS = { "install.sh", "install.ps1" }
  local function keep_scripts(src)
    for _, name in ipairs(LC.SCRIPTS) do
      local from = joinpath(vim.fs.dirname(src), name)
      if uv.fs_stat(from) then
        vim.fn.mkdir(DIR.boot, "p")
        uv.fs_copyfile(from, joinpath(DIR.boot, name))
      end
    end
  end

  -- Cancel and roll back (installer) -------------------------------------------------------
  -- The installer notes how to undo each change just before making it. If it
  -- does not reach the end, those undo steps run newest first, and the
  -- machine is as it was before the install started. There are two ways for
  -- it to stop early:
  --   * An error (LC.fail or any Lua error). The caller in section 4 prints
  --     it, calls LC.rollback() and exits 1.
  --   * Ctrl+C, or the terminal closing (SIGINT, SIGHUP, SIGTERM). In script
  --     mode Neovim treats these as fatal: it prints "Nvim: Caught deadly
  --     signal …" and exits, but on the way out it still runs VimLeavePre.
  --     That autocommand does the rollback and exits 130 (the shell's code for
  --     "interrupted"). libuv delivers Ctrl+C as SIGINT on Windows too.
  --     Neovim ignores further fatal signals while it exits, so a second
  --     Ctrl+C cannot cut the rollback short, and what the rollback itself
  --     runs is started out of the terminal's reach (run_shielded).
  -- Not undone: system packages (apt, winget) installed by this run. Other
  -- programs may use them; the rollback lists them.
  local journal = nil   -- { { what, fn }, ... } while an install is running
  local cancel_hook = nil
  local kept_rows = {}   -- the install's pending records; system packages are among them

  -- Note how to undo the change about to be made. what names it in a warning
  -- if the undo itself fails.
  local function on_undo(what, fn)
    if journal then journal[#journal + 1] = { what, fn } end
  end

  -- Run the undo steps, newest first. Each is taken off the list before it
  -- runs, so a rollback that is itself interrupted and started again goes
  -- on with the steps still left. One that fails is reported and skipped:
  -- the others still put back what they can.
  function LC.rollback(why)
    if not journal then return end
    local pkgs = vim.tbl_filter(function(r) return r[1] == "system-packages.tsv" end, kept_rows)
    local undo = #journal > 0   -- nothing changed yet: say nothing about putting back
    if undo then LC.say(why .. " Putting everything back as it was …") end
    -- A program the installer started (the sync) must stop before the
    -- directories it writes to go away. After Ctrl+C it is already on its
    -- way out (the terminal sent it the same signal); SIGHUP or SIGTERM
    -- may have reached this process only.
    local child = LC.child
    if child and child:is_active() then
      child:kill("sigterm")
      vim.wait(10000, function() return not child:is_active() end, 100)
    end
    while #journal > 0 do
      local step = table.remove(journal)
      local ok, err = pcall(step[2])
      if not ok then LC.warn("Could not undo " .. step[1] .. ": " .. tostring(err)) end
    end
    if undo then LC.say("Rolled back: this install changed nothing.") end
    journal = nil
    if #pkgs > 0 then
      LC.say("System packages installed by this run were kept (other programs may use them):")
      for _, r in ipairs(pkgs) do LC.say("    " .. r[3]) end
    end
  end

  -- Start a journal, and the Ctrl+C hook that rolls it back. rows: the
  -- install's pending records, read by the rollback's closing note.
  local function begin_journal(rows)
    journal, kept_rows = {}, rows
    cancel_hook = vim.api.nvim_create_autocmd("VimLeavePre", {
      once = true,
      callback = function()
        io.write("\n")
        LC.rollback("Cancelled.")
        os.exit(130)
      end,
    })
  end
  -- Reached the end: nothing to roll back any more.
  local function end_journal()
    journal = nil
    if cancel_hook then pcall(vim.api.nvim_del_autocmd, cancel_hook) end
    cancel_hook = nil
  end

  -- The small files an install or import writes, read now, and a function
  -- that puts them back exactly so: files that were absent are deleted, files
  -- added to these directories since (a generation, a set-aside init.lua, a
  -- record) are removed. Plugins and tools are larger and handled per case.
  local function snapshot_files()
    local dirs = { DIR.records, DIR.gens, DIR.rejected, DIR.boot }
    local files = { FILE.init, FILE.marker, FILE.lockfile }
    local listed = {}
    for _, d in ipairs(dirs) do
      listed[d] = {}
      if is_dir(d) then
        for name, kind in vim.fs.dir(d) do
          listed[d][name] = true
          if kind == "file" and d ~= DIR.gens then files[#files + 1] = joinpath(d, name) end
        end
      end
    end
    local saved = {}   -- path -> contents, or false for "did not exist"
    for _, p in ipairs(files) do saved[p] = read_file(p) or false end
    return function()
      for d, names in pairs(listed) do
        if is_dir(d) then
          for name in vim.fs.dir(d) do
            if not names[name] then rm(joinpath(d, name)) end
          end
        end
      end
      for p, text in pairs(saved) do
        if text then write_file(p, text) else os.remove(p) end
      end
    end
  end

  -- Install ---------------------------------------------------------------------------------
  function LC.install(o)
    local src = vim.fs.normalize(vim.fn.fnamemodify(_G.arg[0], ":p"))
    local text = norm(read_file(src) or fail("cannot read " .. src))
    local lk = LC.lock_from_text(text) or fail(src .. " has no LOCK block; is it a Super IDE init.lua?")
    LC.say(("Neovim Super IDE · Neovim %s · %s/%s"):format(lk.neovim, OS, ARCH))
    LC.say("Ctrl+C cancels at any point and puts everything back.")

    -- 1. Look before touching anything.
    if not IS_WIN and lexists(ENTRY) and not link_points_to(ENTRY, joinpath(DIR.opt, "current", "bin", "nvim")) then
      fail(ENTRY .. " already exists and is not Super IDE's. Move it aside, then run this again.")
    end
    local created = new_parents()
    local pending = {}   -- records, written once the data directory is ours
    begin_journal(pending)
    -- Runs last: this Neovim's own log, then parents this run created. Every
    -- Neovim start creates <state>/nvim.log, this installer's included, even
    -- before any of this code runs; an empty one born in this run is ours.
    on_undo("new parent directories", function()
      local log = joinpath(DIR.state, "nvim.log")
      local st = uv.fs_stat(log)
      if st and st.size == 0 and born(st) >= LC.started - 5 then os.remove(log) end
      local sd = uv.fs_stat(DIR.state)
      if sd and born(sd) >= LC.started - 5 then uv.fs_rmdir(DIR.state) end   -- only if empty
      table.sort(created, function(a, b) return #a > #b end)   -- deepest first
      for _ = 1, 2 do for _, d in ipairs(created) do uv.fs_rmdir(d) end end
    end)
    check_system(pending)

    -- 2. Already installed: this file becomes a generation and goes live.
    --    Rolled back by going back to the generation in effect before: its
    --    files exactly as they were, then a sync, because the interrupted
    --    sync may already have moved plugins and tools to the new LOCK.
    if lexists(FILE.marker) then
      LC.say("Super IDE is already installed; importing this file as a generation.")
      local before, before_tag = LC.gen_current(), LC.current_tag()
      local restore = snapshot_files()
      on_undo("the previous generation", function()
        if not before then return restore() end
        -- switch() brings back that generation's Neovim (downloading it if it
        -- was pruned), init.lua and plugin lock; restore() then undoes the
        -- rest to the byte (records, the new generation file, …).
        LC.switch(before)
        restore()
        if before_tag ~= lk.neovim then   -- parsers may have been rebuilt for the other Neovim
          local p = json_read(FILE.pending) or {}
          p.parsers = true
          json_write(FILE.pending, p)
        end
        LC.sync_here(true)
      end)
      local beside = joinpath(vim.fs.dirname(src), "generations")
      if is_dir(beside) and not same_path(beside, DIR.gens) then
        for name in vim.fs.dir(beside) do
          if name:match("%.lua$") and not lexists(gen_path(name)) then uv.fs_copyfile(joinpath(beside, name), gen_path(name)) end
        end
      end
      local name = LC.gen_add(text)
      LC.switch(name)
      keep_scripts(src)
      for _, r in ipairs(pending) do record(unpack(r)) end
      LC.history("import", name)
      LC.sync_here()
      end_journal()
      LC.say("Done. Generation in effect: " .. name)
      return
    end

    -- 3. Fetch our Neovim first: if that fails, nothing has changed.
    local had_opt, had_build = lexists(DIR.opt), lexists(build_dir(lk.neovim))
    on_undo("Neovim " .. lk.neovim, function()
      if not had_opt then rm(DIR.opt) return end
      if not had_build then rm(build_dir(lk.neovim)) end
      rm(joinpath(DIR.opt, ".incoming-" .. lk.neovim))   -- a download cut short
      os.remove(joinpath(DIR.opt, nvim_asset()))
    end)
    vim.fn.mkdir(DIR.opt, "p")
    LC.fetch_neovim(lk.neovim)

    -- 4. Set aside whatever Neovim configuration lives here.
    if only_a_log(DIR.state) then rm(DIR.state) end
    for _, d in ipairs(roots()) do
      if lexists(d) and lexists(d .. "-orig") then
        fail(("both %s and %s exist; resolve that by hand first."):format(d, d .. "-orig"))
      end
    end
    -- Undone by deleting what this install put in Neovim's directories, then
    -- moving each set-aside directory back. A directory that existed and was
    -- not (yet) set aside is not this install's, and is left alone.
    local backups, had_root = {}, {}
    for _, d in ipairs(roots()) do had_root[d] = lexists(d) end
    on_undo("Neovim's directories", function()
      for _, d in ipairs(roots()) do
        local aside = vim.tbl_contains(backups, d)
        if aside or not had_root[d] then rm(d) end
        if aside then mv(d .. "-orig", d); LC.say("Restored " .. d) end
      end
    end)
    for _, d in ipairs(roots()) do
      if lexists(d) then
        mv(d, d .. "-orig")
        backups[#backups + 1] = d
        LC.say("Set aside " .. d .. "  →  " .. d .. "-orig")
      end
    end

    -- 5. State kept by an earlier uninstall. The kept state is deleted only
    --    at the end, so a rollback can still put it back where it was.
    local drop_trash = false
    if is_dir(DIR.trash) then
      local saved = vim.trim(read_file(joinpath(DIR.trash, "saved-at")) or "unknown date")
      if LC.ask(("Restore the state kept by the last uninstall (%s)?"):format(saved), true) then
        local moved = {}
        on_undo("the kept state", function()
          for _, k in ipairs(moved) do mv(DIR[k], joinpath(DIR.trash, k)) end
        end)
        for _, k in ipairs({ "data", "state", "config" }) do
          local from = joinpath(DIR.trash, k)
          if is_dir(from) and not lexists(DIR[k]) then
            -- The uninstall removed parents it had created (~/.config, …) once
            -- empty; they come back here, and are in `created` again.
            vim.fn.mkdir(vim.fs.dirname(DIR[k]), "p")
            mv(from, DIR[k])
            moved[#moved + 1] = k
          end
        end
        for line in vim.gsplit(read_file(joinpath(DIR.trash, "created-dirs")) or "", "\n", { plain = true }) do
          if line ~= "" then created[#created + 1] = line end
        end
        drop_trash = true
        LC.say("Restored plugins, tools, generations and history.")
      elseif LC.ask("Delete that kept state?", false) then
        drop_trash = true
      end
    end

    -- 6. Deploy this file as the first (or next) generation. Restored state
    --    (step 5) gets its small files back exactly; anything else written
    --    here is inside directories step 4's undo deletes.
    on_undo("Super IDE's own files", snapshot_files())
    keep_rejected(read_file(FILE.init))
    write_file(FILE.init, text)
    write_file(FILE.marker, "Neovim Super IDE\n")
    os.remove(FILE.candidate)
    local name = LC.gen_add(text)
    keep_scripts(src)
    json_write(FILE.lockfile, lk.plugins)
    for _, d in ipairs(backups) do record("install.tsv", "backup", d) end
    table.sort(created)
    for _, d in ipairs(vim.fn.uniq(created)) do record("install.tsv", "created-dir", d) end

    -- 7. Make `nvim` start our Neovim. Undone from the rows `pending` holds by
    --    then, exactly as an uninstall undoes them from install.tsv.
    local link = current_link()
    local prev_target = is_link(link) and uv.fs_readlink(link) or nil
    on_undo("the current link", function()
      remove_link(link)
      if prev_target then make_link(prev_target, link) end
    end)
    LC.set_current(lk.neovim)
    on_undo("the nvim command", function() undo_entry(manifest(pending)) end)
    install_entry(pending)

    -- 8. Optional: git commit messages in Super IDE.
    on_undo("git's core.editor", function() undo_git(manifest(pending)) end)
    if exe("git") and (o.git_editor or (not LC.yes and LC.ask("Use Super IDE as git's editor (core.editor)?", false))) then
      local cur = vim.system({ "git", "config", "--global", "--get", "core.editor" }, { text = true }):wait()
      local gitconfig = joinpath(HOME, ".gitconfig")
      if not lexists(gitconfig) then pending[#pending + 1] = { "install.tsv", "gitconfig-created", gitconfig } end
      pending[#pending + 1] = { "install.tsv", "git-editor", cur.code == 0 and vim.trim(cur.stdout) or "<unset>" }
      vim.system({ "git", "config", "--global", "core.editor", "nvim" }):wait()
    end
    for _, r in ipairs(pending) do record(unpack(r)) end
    LC.history("install", name)

    -- 9. Plugins, tools and parsers, installed by the pinned Neovim itself.
    LC.sync_here()
    end_journal()
    if drop_trash then rm(DIR.trash) end
    LC.say("Installed. Generation in effect: " .. name)
    if #backups > 0 then   -- only when step 4 actually set something aside
      LC.say("Your previous configuration is kept as *-orig; it still runs with:  NVIM_APPNAME=nvim-orig nvim")
    end
  end

  -- Uninstall ------------------------------------------------------------------------------
  -- The real work, done by a Neovim that is not using these directories.
  function LC.uninstall(o)
    if o.target then relocate(o.target) end
    if o.wait_pid then
      while uv.kill(o.wait_pid, 0) == 0 do uv.sleep(200) end
    end
    if not lexists(FILE.marker) then fail("Super IDE is not installed in " .. DIR.config) end
    local keep = o.keep
    if keep == nil then keep = LC.ask("Keep Super IDE's state in " .. DIR.trash .. " for a later install?", true) end

    -- Read every record first: their directory is about to move.
    local M = manifest()
    local links = read_records("clangd-links.tsv")
    local excludes = read_records("git-excludes.tsv")
    local packages = read_records("system-packages.tsv")

    -- 1. Changes inside projects: clangd index links, .git/info/exclude lines.
    for _, r in ipairs(links) do
      if link_points_to(r[1], r[2]) then remove_link(r[1]) end
    end
    for _, r in ipairs(excludes) do
      local text = read_file(r[1])
      if text then
        local kept = vim.tbl_filter(function(l) return l ~= r[2] end, vim.split(text, "\n", { plain = true }))
        write_file(r[1], table.concat(kept, "\n"))
      end
    end
    LC.say(("Undid %d clangd link(s) and %d git exclude line(s)."):format(#links, #excludes))

    -- 2. git's editor.
    undo_git(M)

    -- 3. The `nvim` command.
    undo_entry(M)

    -- 4. Super IDE's own state: into the trash, or gone.
    for _, f in ipairs({ "install.tsv", "clangd-links.tsv", "git-excludes.tsv", "candidate.json", "pending.json" }) do
      os.remove(joinpath(DIR.records, f))
    end
    os.remove(FILE.marker)
    rm(DIR.trash)
    if keep then
      vim.fn.mkdir(DIR.trash, "p")
      for _, k in ipairs({ "config", "data", "state" }) do
        if lexists(DIR[k]) then mv(DIR[k], joinpath(DIR.trash, k)) end
      end
      write_file(joinpath(DIR.trash, "saved-at"), os.date("%Y-%m-%d %H:%M") .. "\n")
      write_file(joinpath(DIR.trash, "created-dirs"), table.concat(M["created-dir"] or {}, "\n") .. "\n")
      LC.say("Kept plugins, tools, generations and history in " .. DIR.trash)
    else
      for _, d in ipairs({ DIR.config, DIR.data, DIR.state }) do rm(d) end
    end
    rm(DIR.cache)

    -- 5. The configuration that was here before.
    for _, d in ipairs(M.backup or {}) do
      if lexists(d .. "-orig") then
        if lexists(d) then LC.warn(d .. " exists again; your original stays at " .. d .. "-orig")
        else mv(d .. "-orig", d); LC.say("Restored " .. d) end
      end
    end

    -- 6. Our Neovim, then empty parents created by the install.
    pcall(rm, DIR.opt)
    for _, d in pairs(nvim_dirs("super-ide-uninstall")) do pcall(rm, d) end   -- this process's own log
    local dirs = M["created-dir"] or {}
    table.sort(dirs, function(a, b) return #a > #b end)
    for _ = 1, 2 do for _, d in ipairs(dirs) do uv.fs_rmdir(d) end end

    if #packages > 0 then
      LC.say("System packages installed for Super IDE were kept (other programs may use them):")
      for _, p in ipairs(packages) do LC.say("    " .. p[2]) end
    end
    LC.say("Neovim Super IDE has been removed.")
  end

  -- Hand the uninstall to a Neovim that runs from a temporary copy and waits
  -- for this process to exit: nothing can delete the directories it is using.
  -- From the editor (detached) or the terminal (in front, except on Windows).
  -- Prefix of the uninstaller's working directory in the system temp folder.
  LC.UNINSTALL_PREFIX = "super-ide-uninstall-"

  function LC.uninstall_handoff(keep, from_editor)
    -- The uninstaller runs from a copy of this file (and, on Windows, of
    -- Neovim) in a directory of its own, which must outlive this Neovim:
    --   * Not Neovim's private temp directory (vim.fn.tempname()): Neovim
    --     deletes that directory when it exits, which may be before the
    --     uninstaller has even read its copy.
    --   * In the system temp folder (uv.os_tmpdir(): $TMPDIR or /tmp, %TEMP%
    --     on Windows), under a unique name made by fs_mkdtemp: it creates the
    --     directory atomically, readable by you alone (mode 0700), so another
    --     user's file of the same name can neither collide with it nor
    --     redirect it elsewhere.
    -- The directory stays afterwards, with the log in it. Leftovers of earlier
    -- uninstalls are removed first, if they are yours: Windows never empties
    -- %TEMP% by itself, and each one holds a copy of Neovim there.
    local base = uv.os_tmpdir()
    for name, kind in vim.fs.dir(base) do
      if kind == "directory" and vim.startswith(name, LC.UNINSTALL_PREFIX) then
        local old = joinpath(base, name)
        local st = uv.fs_lstat(old)
        if st and (IS_WIN or st.uid == uv.getuid()) then pcall(rm, old) end
      end
    end
    local tmp, err = uv.fs_mkdtemp(joinpath(base, LC.UNINSTALL_PREFIX .. "XXXXXX"))
    if not tmp then fail("cannot create a working directory in " .. base .. ": " .. tostring(err)) end
    local script = joinpath(tmp, "init.lua")
    uv.fs_copyfile(FILE.init, script)
    local bin = vim.v.progpath
    if IS_WIN then   -- a running .exe cannot be deleted: run a copy that lives in TEMP
      copy_tree(vim.fs.dirname(vim.fs.dirname(bin)), joinpath(tmp, "nvim"))
      bin = build_exe(joinpath(tmp, "nvim"))
    end
    local log = joinpath(tmp, "uninstall.log")
    local args = { "--clean", "-l", script, "uninstall", "--relocated", "--yes", keep and "--keep-state" or "--discard-state",
      "--target", APPNAME, "--log", log }
    local env = { NVIM_APPNAME = "super-ide-uninstall" }
    if from_editor or IS_WIN then
      vim.list_extend(args, { "--wait-pid", tostring(uv.os_getpid()) })
      -- detached = true: the uninstaller gets its own process group and
      -- outlives this Neovim; unref() lets this one exit without waiting.
      local handle = uv.spawn(bin, { args = args, env = env_with(env), detached = true }, function() end)
      if handle then handle:unref() end
      return log
    end
    os.exit(run_tty(bin, args, env))
  end
end

-- ── Script mode ends here ────────────────────────────────────────────────────
-- `nvim -l init.lua <command>` runs the command and leaves before any editor
-- code (options, plugins, UI) is touched. A normal start has no arg[0].
if SCRIPT then
  local HELP = [[
Neovim Super IDE — script commands (README.md is the full guide)

  nvim -l init.lua install [--yes] [--git-editor]
      Install Super IDE from this file. When it is already installed, this
      file is imported as a new generation and becomes the live one.

  nvim -l ~/.config/nvim/init.lua uninstall [--keep-state | --discard-state] [--yes]
      Remove Super IDE and bring back the configuration found before install.

  nvim -l init.lua help
      This text.

  Normally started for you by install.sh / install.ps1, which first add the
  system packages and fetch the pinned Neovim. They pass one more option:
      --archive FILE   the Neovim release archive they downloaded; unpacked
                       instead of downloading it a second time
]]

  -- _G.arg is the argument list of `nvim -l init.lua <args>`: arg[0] is the
  -- script's path, arg[1] the command, arg[2...] its options.
  local function parse(a)
    local o, i = { cmd = a[1] }, 2
    while a[i] do
      local x = a[i]
      if x == "--yes" or x == "-y" then o.yes = true
      elseif x == "--git-editor" then o.git_editor = true
      elseif x == "--keep-state" then o.keep = true
      elseif x == "--discard-state" then o.keep = false
      elseif x == "--relocated" then o.relocated = true
      elseif x == "--wait-pid" then i = i + 1; o.wait_pid = tonumber(a[i])
      elseif x == "--target" then i = i + 1; o.target = a[i]
      elseif x == "--log" then i = i + 1; o.log = a[i]
      elseif x == "--archive" then i = i + 1; o.archive = a[i]
      else LC.fail("unknown option " .. x .. " (see: nvim -l init.lua help)") end
      i = i + 1
    end
    return o
  end

  -- Every failure is an error() with a message (LC.fail); pcall catches it
  -- here, so the user sees one "xx" line and exit code 1, not a stack trace.
  local ok, err = pcall(function()
    local o = parse(_G.arg)
    LC.yes, LC.log = o.yes or false, o.log
    -- Absolute, because the installer later runs with other working directories.
    LC.archive = o.archive and vim.fn.fnamemodify(o.archive, ":p") or nil
    if o.cmd == "install" then
      LC.install(o)
    elseif o.cmd == "uninstall" then
      if o.relocated then return LC.uninstall(o) end   -- the handed-over half
      if not LC.lexists(FILE.marker) then LC.fail("Super IDE is not installed in " .. DIR.config) end
      local keep = o.keep
      if keep == nil then
        keep = LC.ask("Keep Super IDE's state (plugins, tools, generations) in " .. DIR.trash .. " for a later install?", true)
      end
      local log = LC.uninstall_handoff(keep, false)   -- Unix: runs here and exits
      LC.say("Uninstalling in the background (Windows cannot delete a running Neovim); log: " .. log)
    elseif o.cmd == nil or o.cmd == "help" or o.cmd == "--help" or o.cmd == "-h" then
      io.write(HELP)
    else
      LC.fail("unknown command '" .. o.cmd .. "' (see: nvim -l init.lua help)")
    end
  end)
  if not ok then
    io.stderr:write("xx  ", tostring(err), "\n")
    if LC.log then
      local f = io.open(LC.log, "a")
      if f then f:write("xx  ", tostring(err), "\n"); f:close() end
    end
    -- An install that stopped halfway puts back what it changed (section 3,
    -- "Cancel and roll back"); for any other command this does nothing.
    LC.rollback("Installation stopped.")
    os.exit(1)
  end
  os.exit(0)   -- leave here: none of the editor code below runs in script mode
end

-- ============================================================================
-- 4. Sandbox — private directories, caches and PATH for this Neovim
-- ============================================================================
-- From here on we are the editor, and these directories are ours to write.
-- <leader> in a mapping stands for this key. It must be set before any
-- mapping is made: a mapping records the leader at the time it is created.
vim.g.mapleader = SETTINGS.leader
-- vim._core.ui2 is internal and experimental in 0.12, hence pcall.
if SETTINGS.ui2 then pcall(function() require("vim._core.ui2").enable({}) end) end

for _, d in ipairs({ DIR.bin, DIR.runtimes, DIR.records, DIR.gens, DIR.clangd, DIR.xdg, DIR.dl }) do
  vim.fn.mkdir(d, "p")   -- "p": create parents too, and no error if it exists
end

-- Add a directory to PATH for this Neovim process only. Children inherit it;
-- the shell you started from never sees it.
local function path_add(dir, prepend)
  if not dir or vim.fn.isdirectory(dir) == 0 then return end
  local entry = IS_WIN and (dir:gsub("/", "\\")) or dir
  local current = vim.env.PATH or ""
  for e in vim.gsplit(current, PATH_SEP, { plain = true }) do
    if e == entry then return end
  end
  vim.env.PATH = prepend and (entry .. PATH_SEP .. current) or (current .. PATH_SEP .. entry)
end

-- Package managers love to scribble caches into $HOME. Keep the ones Mason
-- triggers inside our sandbox. (Go's module cache and Cargo's registry are
-- left alone: they belong to toolchains you already own.)
vim.env.npm_config_cache = joinpath(DIR.cache, "npm")
vim.env.npm_config_update_notifier = "false"
vim.env.PIP_CACHE_DIR = joinpath(DIR.cache, "pip")
vim.env.PIP_DISABLE_PIP_VERSION_CHECK = "1"

-- wget (Mason's fallback downloader) keeps an HSTS database in $HOME; give it
-- a private config that turns that off — unless you already configure wget.
if not vim.env.WGETRC and vim.fn.filereadable(joinpath(HOME, ".wgetrc")) == 0 then
  local rc = joinpath(DIR.home, "wgetrc")
  if vim.fn.filereadable(rc) == 0 then vim.fn.writefile({ "hsts = off" }, rc) end
  vim.env.WGETRC = rc
end

path_add(DIR.bin)   -- appended: a tool you installed yourself always wins

-- Windows: winget's LLVM leaves clang off PATH (see LLVM_BIN). Parsers and
-- other C builds need a compiler, so add it for this Neovim only, and only
-- when no compiler is reachable already.
if LLVM_BIN and not (exe("clang") or exe("gcc") or exe("cl")) then path_add(LLVM_BIN) end

-- ============================================================================
-- 5. Editor options — display, editing, indentation, clipboard
-- ============================================================================
-- vim.opt.X = value is :set X=value (the primer at the top lists such forms).
local o = vim.opt

o.number         = true
o.relativenumber = true
o.termguicolors  = true
o.signcolumn     = "yes"
o.splitbelow     = true
o.splitright     = true
o.updatetime     = 120
o.mouse          = "a"     -- keyboard first; the mouse is for the occasional selection
o.ignorecase     = true
o.smartcase      = true
o.scrolloff      = 7
o.undofile       = true    -- undo history survives restarts (kept under stdpath("state"))
o.confirm        = true    -- ask instead of failing on :q with unsaved changes

-- Cursor shape follows the mode: block / beam / underline (terminal permitting).
o.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50"

-- Two-space indentation is the house default; section 6 adapts it per
-- language and defers to .editorconfig whenever a project ships one.
o.tabstop     = 2
o.softtabstop = 2
o.shiftwidth  = 2
o.expandtab   = true
o.smarttab    = true
o.autoindent  = true
o.smartindent = true

-- Extra filetype rules: assembly sources and JSP pages.
-- vim.filetype.add() teaches Neovim filename → filetype rules; the filetype
-- then decides syntax, indentation, language server and so on.
vim.filetype.add({
  extension = { S = "asm", s = "asm", asm = "asm", inc = "asm", jsp = "jsp" },
})

-- Legacy providers serve old remote plugins only. Switching them off keeps
-- startup free of probes and :checkhealth free of noise.
-- vim.g.loaded_X_provider = 0 tells Neovim that provider is "already loaded",
-- so it never goes looking for it.
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0
if not SETTINGS.python_provider then vim.g.loaded_python3_provider = 0 end

-- Clipboard. Over SSH there is rarely a clipboard tool on the server, so we
-- copy through OSC 52: the escape sequence travels back to your local
-- terminal, which puts the text on your local clipboard. Pasting reads from a
-- local cache, because few terminals allow programs to read the clipboard.
do
  local remote = vim.env.SSH_TTY or vim.env.SSH_CONNECTION
  local forwarded = (vim.env.WAYLAND_DISPLAY and exe("wl-copy"))
    or (vim.env.DISPLAY and (exe("xclip") or exe("xsel")))
  if remote and not forwarded then
    local osc52 = require("vim.ui.clipboard.osc52")
    local cache = { {}, "v" }
    local function copy(reg)
      local send = osc52.copy(reg)
      return function(lines, regtype)
        cache = { lines, regtype }
        send(lines)
      end
    end
    local function paste() return cache end
    -- vim.g.clipboard replaces Neovim's search for a clipboard tool: "copy"
    -- and "paste" give a function per register ("+" and "*"). :help clipboard
    vim.g.clipboard = {
      name  = "OSC 52 (copy) + local cache (paste)",
      copy  = { ["+"] = copy("+"), ["*"] = copy("*") },
      paste = { ["+"] = paste, ["*"] = paste },
    }
  end
  -- 'clipboard' = "unnamedplus": plain y/p use the system clipboard ("+).
  if vim.g.clipboard or vim.fn.has("clipboard") == 1 then
    o.clipboard = "unnamedplus"
  end
end

-- ============================================================================
-- 6. Habits
-- ============================================================================

-- Cursor cross: cursorline + cursorcolumn in the active window only,
-- toggled with <leader>fc. Colours come from the colorscheme; if it forgets
-- CursorColumn, we borrow CursorLine's.
vim.g.cursor_cross = true
local NO_CROSS = { superide = true, ["neo-tree"] = true, fzf = true, toggleterm = true, lazy = true, mason = true }

-- vim.wo[win] holds the options of one window; vim.bo[buf] those of one buffer.
local function cross_apply(win, on)
  if not vim.api.nvim_win_is_valid(win) then return end   -- the window may be closed already
  local buf = vim.api.nvim_win_get_buf(win)
  if on and (NO_CROSS[vim.bo[buf].filetype] or vim.bo[buf].buftype == "terminal") then on = false end
  vim.wo[win].cursorline = on
  vim.wo[win].cursorcolumn = on
end

local function cross_fix_hl()
  -- nvim_get_hl(0, ...) reads a highlight group from the global namespace (0);
  -- link = false follows links to the colours actually used.
  local hl = vim.api.nvim_get_hl(0, { name = "CursorColumn", link = false })
  if not (hl.bg or hl.ctermbg or hl.reverse or hl.underline) then
    vim.api.nvim_set_hl(0, "CursorColumn", { link = "CursorLine" })
  end
end

-- One augroup for this section's autocmds (clear = true: never registered twice).
local habits = vim.api.nvim_create_augroup("super_ide_habits", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", { group = habits, callback = cross_fix_hl })
-- A list of events: the callback runs for each of them.
vim.api.nvim_create_autocmd({ "VimEnter", "WinEnter", "BufWinEnter", "FileType" }, {
  group = habits,
  callback = function() cross_apply(vim.api.nvim_get_current_win(), vim.g.cursor_cross) end,
})
vim.api.nvim_create_autocmd("WinLeave", {
  group = habits,
  callback = function() cross_apply(vim.api.nvim_get_current_win(), false) end,
})
-- A Normal-mode ("n") mapping whose right-hand side is a Lua function.
vim.keymap.set("n", "<leader>fc", function()
  vim.g.cursor_cross = not vim.g.cursor_cross
  cross_apply(vim.api.nvim_get_current_win(), vim.g.cursor_cross)
end, { desc = "Toggle cursor cross (line/column)" })

-- Column guides at 80/100/120: gentle fences against runaway lines.
local function guides(on)
  vim.g.column_guides = on
  vim.opt.colorcolumn = on and "80,100,120" or ""
end
guides(true)
local function guides_toggle() guides(not vim.g.column_guides) end
-- Commands without arguments: opts may be empty (nargs defaults to 0).
vim.api.nvim_create_user_command("ColumnGuidesToggle", guides_toggle, {})
vim.api.nvim_create_user_command("ColumnGuidesOn", function() guides(true) end, {})
vim.api.nvim_create_user_command("ColumnGuidesOff", function() guides(false) end, {})
vim.keymap.set("n", "<leader>cg", guides_toggle, { desc = "Toggle column guides (80/100/120)" })

-- Return to the last cursor position when a file is reopened. Scheduled so
-- that the filetype is already known when we check the exclusions.
local NO_RESTORE = { gitcommit = true, gitrebase = true, help = true, qf = true, ["neo-tree"] = true }
vim.api.nvim_create_autocmd("BufReadPost", {
  group = habits,
  callback = function(ev)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(ev.buf) or vim.bo[ev.buf].buftype ~= "" then return end
      if NO_RESTORE[vim.bo[ev.buf].filetype] then return end
      if vim.api.nvim_get_current_buf() ~= ev.buf then return end
      -- The '"' mark is where the cursor was when the buffer was last left;
      -- Neovim keeps it across sessions in its shada file.
      local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
      if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
        pcall(vim.api.nvim_win_set_cursor, 0, mark)
      end
    end)
  end,
})

-- Briefly highlight what was just yanked.
vim.api.nvim_create_autocmd("TextYankPost", {
  group = habits,
  callback = function() vim.hl.on_yank({ timeout = 150 }) end,
})

-- ============================================================================
-- 7. Global keymaps
-- ============================================================================
-- map(mode, lhs, rhs, opts) — the primer at the top explains the arguments.
local map = vim.keymap.set

-- Window navigation, with arrow fallbacks for terminals that mangle <C-h> or
-- swallow <C-l>. <BS> is deliberately left alone: in Normal mode it keeps
-- Vim's own meaning, one character back without touching the text.
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })
map("n", "<C-Left>", "<C-w>h", { desc = "Window left (alternative)" })
map("n", "<C-Right>", "<C-w>l", { desc = "Window right (alternative)" })

-- Buffers.
map("n", "<F2>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "<F3>", "<cmd>bnext<CR>", { desc = "Next buffer" })

-- The config itself, and a quiet search highlight.
map("n", "<leader><leader>ev", "<cmd>edit $MYVIMRC<CR>", { desc = "Edit init.lua" })
map("n", "<leader><leader><space>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Insert mode: <Left> at column 1 climbs to the end of the previous line;
-- <Right> at the end of a line drops to the start of the next one.
-- expr = true: the function does not act itself, it returns the keys that
-- Neovim then presses ("<Esc>kA" = leave Insert, line up, append at the end).
-- col(".") is the cursor column, col("$") one past the end of the line.
map("i", "<Left>", function()
  if vim.fn.col(".") == 1 and vim.fn.line(".") > 1 then return "<Esc>kA" end
  return "<Left>"
end, { expr = true, desc = "Wrap-left" })
map("i", "<Right>", function()
  if vim.fn.col(".") >= vim.fn.col("$") and vim.fn.line(".") < vim.fn.line("$") then return "<Esc>j0i" end
  return "<Right>"
end, { expr = true, desc = "Wrap-right" })

-- Terminal mode: <Esc> returns to Normal mode — except inside the fuzzy
-- finder, where <Esc> must keep its job of closing the picker.
-- <C-\><C-n> is the key sequence that leaves Terminal mode.
map("t", "<Esc>", function()
  return vim.bo.filetype == "fzf" and "<Esc>" or [[<C-\><C-n>]]
end, { expr = true, desc = "Terminal normal mode" })

-- <C-]>: definition via LSP when a server is attached, otherwise a ctags tags file.
map("n", "<C-]>", function()
  -- get_clients({ bufnr = 0, method = ... }): the language servers attached to
  -- the current buffer (0) that can answer that request.
  if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/definition" }) > 0 then
    vim.lsp.buf.definition()
  elseif #vim.fn.tagfiles() > 0 then
    local word = vim.fn.expand("<cword>")
    if word ~= "" then pcall(vim.cmd.tag, word) end
  else
    notify("No language server attached and no tags file (try :IDEDoctor or ctags -R).", vim.log.levels.WARN)
  end
end, { desc = "Go to definition (LSP or tags)" })

-- Neovim 0.11+ ships gra/gri/grn/grr/grt/grx. Our habit is a bare `gr` for
-- references, and the prefix would make it wait for 'timeoutlen'; each of
-- those actions already has a home key (see section 10), so the defaults go.
for _, lhs in ipairs({ "gra", "gri", "grn", "grr", "grt", "grx" }) do
  pcall(vim.keymap.del, "n", lhs)
  pcall(vim.keymap.del, "x", lhs)
end

-- ============================================================================
-- 8. Language registry
-- ============================================================================
-- One row per language. Adding a language means adding a row — nothing else.
--
--   ft       filetypes this row answers for
--   ts       Tree-sitter parsers to install (highlighting, indent, rainbow)
--   lsp      language-server configs to enable (names from nvim-lspconfig)
--   tools    executables to provide:
--              bin    = executable name looked up on PATH
--              mason  = Mason package that provides it when PATH does not
--              server = the LSP config this binary powers (enabled once present)
--              needs  = runtime the installer needs: node | python | go | cargo | php
--              probe  = optional function proving the binary truly works
--              apt    = Debian package to offer when Mason has no build for this machine
--   format   conform.nvim formatters per filetype (first match wins with stop = true)
--   dap      debug adapter key (see section 11)
--   indent   { width = n, tabs = bool }  — defaults to 2 spaces
--   jdk      true when the language server needs a JDK 21+ runtime
local NODE, PY, GO, CARGO, PHP = "node", "python", "go", "cargo", "php"

local PRETTIER = { bin = "prettier", mason = "prettier", needs = NODE }

local LANGS = {
  c = {
    label = "C/C++", ft = { "c", "cpp", "objc", "objcpp", "cuda" }, ts = { "c", "cpp", "cuda" },
    lsp = { "clangd" },
    tools = {
      { bin = "clangd", mason = "clangd", server = "clangd", apt = "clangd" },
      { bin = "clang-format", mason = "clang-format", needs = PY, apt = "clang-format" },
    },
    format = { c = { "clang_format" }, cpp = { "clang_format" }, cuda = { "clang_format" } },
    dap = "codelldb", indent = { width = 2 },
  },
  python = {
    label = "Python", ft = { "python" }, ts = { "python" },
    lsp = { "basedpyright" },
    tools = {
      { bin = "basedpyright-langserver", mason = "basedpyright", server = "basedpyright", needs = PY },
      { bin = "ruff", mason = "ruff" },
    },
    format = { python = { "ruff_fix", "ruff_format" } },
    dap = "debugpy", indent = { width = 4 },
  },
  rust = {
    label = "Rust", ft = { "rust" }, ts = { "rust" },
    lsp = { "rust_analyzer" },
    tools = {
      -- rustup installs a proxy named rust-analyzer even when the component
      -- is absent, so existence alone proves nothing: ask it for a version.
      { bin = "rust-analyzer", mason = "rust-analyzer", server = "rust_analyzer",
        probe = function() return vim.system({ "rust-analyzer", "--version" }):wait().code == 0 end },
    },
    format = { rust = { "rustfmt" } },   -- ships with rustup (`rustup component add rustfmt`)
    dap = "codelldb", indent = { width = 4 },
  },
  go = {
    label = "Go", ft = { "go", "gomod", "gowork", "gotmpl" }, ts = { "go", "gomod", "gowork", "gosum" },
    lsp = { "gopls" },
    tools = {
      { bin = "gopls", mason = "gopls", server = "gopls", needs = GO },
      { bin = "goimports", mason = "goimports", needs = GO },
    },
    format = { go = { "goimports", "gofmt", stop = true } },
    dap = "delve", indent = { width = 4, tabs = true },
  },
  java = {
    label = "Java", ft = { "java" }, ts = { "java" },
    lsp = { "jdtls" }, jdk = true,
    tools = { { bin = "jdtls", mason = "jdtls", server = "jdtls", needs = PY } },
    format = {},                         -- jdtls formats through the LSP fallback
    indent = { width = 4 },
  },
  web = {
    label = "JavaScript/TypeScript",
    ft = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
    ts = { "javascript", "typescript", "tsx", "jsdoc" },
    lsp = { "vtsls", "eslint" },
    tools = {
      { bin = "vtsls", mason = "vtsls", server = "vtsls", needs = NODE },
      { bin = "vscode-eslint-language-server", mason = "eslint-lsp", server = "eslint", needs = NODE },
      PRETTIER,
    },
    format = {
      javascript = { "prettier" }, javascriptreact = { "prettier" },
      typescript = { "prettier" }, typescriptreact = { "prettier" },
    },
    indent = { width = 2 },
  },
  html = {
    label = "HTML/JSP", ft = { "html", "jsp" }, ts = { "html" },
    lsp = { "html", "emmet_language_server" },
    tools = {
      { bin = "vscode-html-language-server", mason = "html-lsp", server = "html", needs = NODE },
      { bin = "emmet-language-server", mason = "emmet-language-server", server = "emmet_language_server", needs = NODE },
      PRETTIER,
    },
    format = { html = { "prettier" } },
    indent = { width = 2 },
  },
  css = {
    label = "CSS/SCSS/Less", ft = { "css", "scss", "less" }, ts = { "css", "scss" },
    lsp = { "cssls" },
    tools = {
      { bin = "vscode-css-language-server", mason = "css-lsp", server = "cssls", needs = NODE },
      PRETTIER,
    },
    format = { css = { "prettier" }, scss = { "prettier" }, less = { "prettier" } },
    indent = { width = 2 },
  },
  php = {
    label = "PHP", ft = { "php" }, ts = { "php", "phpdoc" },
    lsp = { "intelephense" },
    tools = {
      { bin = "intelephense", mason = "intelephense", server = "intelephense", needs = NODE },
      { bin = "php-cs-fixer", mason = "php-cs-fixer", needs = PHP },
    },
    format = { php = { "php_cs_fixer" } },
    indent = { width = 4 },
  },
  asm = {
    label = "Assembly", ft = { "asm", "nasm", "vmasm" }, ts = { "asm", "nasm" },
    lsp = { "asm_lsp" },
    tools = { { bin = "asm-lsp", mason = "asm-lsp", server = "asm_lsp", needs = CARGO } },
    format = {},
    indent = { width = 2 },
  },
  lua = {
    label = "Lua", ft = { "lua" }, ts = { "lua", "luadoc" },
    lsp = { "lua_ls" },
    tools = {
      { bin = "lua-language-server", mason = "lua-language-server", server = "lua_ls" },
      { bin = "stylua", mason = "stylua" },
    },
    format = { lua = { "stylua" } },
    indent = { width = 2 },
  },
  shell = {
    label = "Shell", ft = { "sh", "bash", "zsh" }, ts = { "bash" },
    lsp = { "bashls" },
    tools = {
      { bin = "bash-language-server", mason = "bash-language-server", server = "bashls", needs = NODE },
      { bin = "shellcheck", mason = "shellcheck" },   -- bashls lints through it
      { bin = "shfmt", mason = "shfmt" },
    },
    format = { sh = { "shfmt" }, bash = { "shfmt" } },
    indent = { width = 2 },
  },
  json = {
    label = "JSON", ft = { "json", "jsonc", "json5" }, ts = { "json", "json5" },
    lsp = { "jsonls" },
    tools = {
      { bin = "vscode-json-language-server", mason = "json-lsp", server = "jsonls", needs = NODE },
      PRETTIER,
    },
    format = { json = { "prettier" }, jsonc = { "prettier" } },
    indent = { width = 2 },
  },
  yaml = {
    label = "YAML", ft = { "yaml" }, ts = { "yaml" },
    lsp = { "yamlls" },
    tools = {
      { bin = "yaml-language-server", mason = "yaml-language-server", server = "yamlls", needs = NODE },
      PRETTIER,
    },
    format = { yaml = { "prettier" } },
    indent = { width = 2 },
  },
  toml = {
    label = "TOML", ft = { "toml" }, ts = { "toml" },
    lsp = { "taplo" },
    tools = { { bin = "taplo", mason = "taplo", server = "taplo" } },
    format = { toml = { "taplo" } },
    indent = { width = 2 },
  },
  markdown = {
    label = "Markdown", ft = { "markdown" }, ts = { "markdown", "markdown_inline" },
    lsp = { "marksman" },
    tools = {
      { bin = "marksman", mason = "marksman", server = "marksman" },
      PRETTIER,
    },
    format = { markdown = { "prettier" } },
    indent = { width = 2 },
  },
  cmake = {
    label = "CMake", ft = { "cmake" }, ts = { "cmake" },
    lsp = { "neocmake" },
    tools = { { bin = "neocmakelsp", mason = "neocmakelsp", server = "neocmake" } },
    format = {},
    indent = { width = 2 },
  },
  docker = {
    label = "Dockerfile", ft = { "dockerfile" }, ts = { "dockerfile" },
    lsp = { "dockerls" },
    tools = { { bin = "docker-langserver", mason = "dockerfile-language-server", server = "dockerls", needs = NODE } },
    format = {},
    indent = { width = 2 },
  },
  xml = {
    label = "XML", ft = { "xml", "xsd", "xsl", "xslt", "svg" }, ts = { "xml" },
    lsp = { "lemminx" },
    tools = { { bin = "lemminx", mason = "lemminx", server = "lemminx" } },
    format = {},
    indent = { width = 2 },
  },
  sql = {
    label = "SQL", ft = { "sql", "mysql", "plsql" }, ts = { "sql" },
    lsp = {},
    tools = { { bin = "sql-formatter", mason = "sql-formatter", needs = NODE } },
    format = { sql = { "sql_formatter" }, mysql = { "sql_formatter" } },
    indent = { width = 2 },
  },
  make = {
    label = "Make", ft = { "make" }, ts = { "make" },
    lsp = {}, tools = {}, format = {},
    indent = { width = 8, tabs = true },   -- recipes demand real <Tab> characters
  },
  vim = {
    label = "Vim script", ft = { "vim", "help" }, ts = { "vim", "vimdoc" },
    lsp = {}, tools = {}, format = {},
    indent = { width = 2 },
  },
}

-- filetype -> language id
local FT_LANG = {}
for id, L in pairs(LANGS) do
  L.id = id
  for _, ft in ipairs(L.ft) do FT_LANG[ft] = id end
end
local function lang_of(ft) return LANGS[FT_LANG[ft or ""] or ""] end

-- Indentation per language, applied after ftplugins (hence the schedule) and
-- only when the project has not spoken through .editorconfig.
vim.api.nvim_create_autocmd("FileType", {
  group = habits,
  callback = function(ev)
    vim.schedule(function()
      local buf = ev.buf
      if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
      -- Neovim's built-in .editorconfig support leaves what it applied in
      -- the buffer variable b:editorconfig.
      local ec = vim.b[buf].editorconfig
      if type(ec) == "table" and (ec.indent_style or ec.indent_size or ec.tab_width) then return end
      local L = lang_of(vim.bo[buf].filetype)
      local ind = L and L.indent or { width = 2 }
      vim.bo[buf].expandtab = not ind.tabs
      vim.bo[buf].tabstop = ind.width
      vim.bo[buf].shiftwidth = ind.width
      vim.bo[buf].softtabstop = ind.tabs and 0 or ind.width
    end)
  end,
})

-- ============================================================================
-- 9. Provisioning — fetch what a language needs, the first time it is needed
-- ============================================================================
local P = {
  busy   = {},   -- label -> true while something is being fetched (shown in the statusline)
  ready  = {},   -- language id -> true once provisioned this session
  failed = {},   -- language id -> list of human-readable problems
  offered = {},  -- system dependency -> true once offered this session
}

local function busy(label, on)
  P.busy[label] = on or nil
  -- busy() may be called from a fast callback: redraw the statusline later.
  vim.schedule(function() pcall(vim.cmd.redrawstatus) end)
end

-- Run `work(done)` once per key, however many callers ask at the same time;
-- every caller's callback receives the same result.
local inflight = {}
local function once(key, work, cb)
  if inflight[key] then
    table.insert(inflight[key], cb)
    return
  end
  inflight[key] = { cb }
  work(function(...)
    local waiters = inflight[key]
    inflight[key] = nil
    -- pack_len/unpack_len keep the arguments exactly, nil holes included
    -- (a plain {...} would lose a trailing nil).
    local args = vim.F.pack_len(...)
    for _, f in ipairs(waiters) do
      vim.schedule(function() f(vim.F.unpack_len(args)) end)
    end
  end)
end

-- Callbacks from vim.system and friends arrive in a "fast" context where most
-- of the editor API is off limits; this hops back onto the main loop.
local function main(fn) return vim.schedule_wrap(fn) end

-- A tiny parallel join: start every job, call `done(results)` when all finish.
local function all(jobs, done)
  local n, results = #jobs, {}
  if n == 0 then return done(results) end
  for i, job in ipairs(jobs) do
    job(function(ok, why)
      results[i] = { ok = ok, why = why }
      n = n - 1
      if n == 0 then done(results) end
    end)
  end
end

-- ---------------------------------------------------------------------------
-- 9a. System dependencies — the only things we cannot fetch ourselves
-- ---------------------------------------------------------------------------
local function python_cmd() return exe("python3") and "python3" or (exe("python") and "python") or nil end

local SYSDEPS = {
  cc = {
    what = "a C compiler (Tree-sitter builds its parsers with it)",
    ok = function() return exe("cc") or exe("gcc") or exe("clang") or exe("cl") end,
    apt = "build-essential", mac = "xcode-select --install", win = "winget install -e --id LLVM.LLVM",
  },
  git = {
    what = "git", ok = function() return exe("git") end,
    apt = "git", mac = "xcode-select --install", win = "winget install -e --id Git.Git",
  },
  curl = { what = "curl", ok = function() return exe("curl") end, apt = "curl" },
  unzip = { what = "unzip (Mason unpacks .zip releases)", ok = function() return IS_WIN or exe("unzip") end, apt = "unzip" },
  venv = {
    what = "python3-venv (Mason installs Python tools into private venvs)",
    ok = function(self)
      if self.cached then return true end
      local py = python_cmd()
      self.cached = py ~= nil and vim.system({ py, "-c", "import ensurepip, venv" }):wait().code == 0
      return self.cached
    end,
    apt = "python3-venv",
  },
}

local function sysdep_command(dep)
  if OS == "linux" then
    if dep.apt and exe("apt-get") then return "sudo apt-get install -y " .. dep.apt end
    return nil
  end
  return OS == "mac" and dep.mac or dep.win
end

-- Open a floating terminal running `cmd`; `on_exit(code)` fires when it ends.
local function float_term(cmd, title, on_exit)
  -- nvim_create_buf(listed, scratch): not in the buffer list, never saved.
  local buf = vim.api.nvim_create_buf(false, true)
  local w = math.min(110, math.floor(vim.o.columns * 0.85))
  local h = math.min(30, math.floor(vim.o.lines * 0.6))
  -- nvim_open_win(buf, enter, config): relative = "editor" makes a floating
  -- window, placed by row/col; enter = true moves the cursor into it.
  vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
    border = "rounded", title = " " .. title .. " ", title_pos = "center",
  })
  -- jobstart with term = true runs cmd in a terminal inside the current
  -- buffer (the float), so prompts such as sudo's password work there.
  vim.fn.jobstart(cmd, {
    term = true,
    on_exit = function(_, code) vim.schedule(function() on_exit(code) end) end,
  })
  vim.cmd.startinsert()   -- Terminal mode: keys go to the program
end

-- Offer to install a missing system dependency. Nothing runs without consent;
-- in headless mode we can only print the command.
local function offer_sysdep(key, cb)
  local dep = SYSDEPS[key]
  if dep:ok() then return cb(true) end
  once("sysdep:" .. key, function(done)
    local cmd = sysdep_command(dep)
    if P.offered[key] or HEADLESS or not cmd then
      if not P.offered[key] then
        notify(("Missing %s.%s"):format(dep.what, cmd and ("\nInstall with:  " .. cmd) or
          "\nInstall it with your system package manager, then run :IDEInstall."), vim.log.levels.WARN)
      end
      P.offered[key] = true
      return done(false, "missing " .. dep.what)
    end
    P.offered[key] = true
    -- vim.ui.select(items, opts, on_choice) shows a menu (Neovim's own: a
    -- numbered list); on_choice(item, index) gets nil when it is dismissed.
    vim.ui.select({ "Install now (opens a terminal)", "Show me the command", "Not now" }, {
      prompt = "Super IDE needs " .. dep.what .. ":",
    }, function(_, idx)
      if idx == 1 then
        float_term(cmd, "Installing " .. key, function(code)
          if code == 0 and dep:ok() then
            record("system-packages.tsv", OS, dep.apt or key, cmd)
            notify("Installed " .. dep.what .. ".")
            done(true)
          else
            done(false, "installing " .. dep.what .. " failed")
          end
        end)
      else
        if idx == 2 then notify("Run this yourself, then :IDEInstall\n  " .. cmd) end
        done(false, "missing " .. dep.what)
      end
    end)
  end, cb)
end

-- ---------------------------------------------------------------------------
-- 9b. Downloads — plain curl + tar, available on all three platforms
--     (Windows 10+ ships both, and its tar unpacks .zip as well).
-- ---------------------------------------------------------------------------
local function download_and_extract(url, dest, opts, cb)
  opts = opts or {}
  local file = joinpath(DIR.dl, opts.name or url:match("[^/?]+$") or "download")
  vim.fn.delete(dest, "rf")
  vim.fn.mkdir(dest, "p")
  -- Asynchronous: vim.system returns at once; main() brings the callback back
  -- onto the main loop when curl ends, then tar runs the same way.
  vim.system({ "curl", "-fsSL", "--retry", "2", "-o", file, url }, {}, main(function(r)
    if r.code ~= 0 then return cb(false, "download failed: " .. url) end
    local args = { "tar", "-xf", file, "-C", dest }
    if opts.strip then table.insert(args, "--strip-components=" .. opts.strip) end
    vim.system(args, {}, main(function(t)
      os.remove(file)
      if t.code == 0 then return cb(true) end
      cb(false, "extracting failed: " .. (t.stderr or ""))
    end))
  end))
end

-- Resolve the newest release tag of a GitHub repository through the
-- /releases/latest redirect: no API token, no rate limit.
local function github_latest(repo, cb)
  vim.system({ "curl", "-fsSLI", "-o", NULL_DEV, "-w", "%{url_effective}",
    SETTINGS.github .. "/" .. repo .. "/releases/latest" }, { text = true }, main(function(r)
    cb(r.code == 0 and r.stdout:match("/releases/tag/([^/%s]+)%s*$") or nil)
  end))
end

-- ---------------------------------------------------------------------------
-- 9c. Portable command-line tools (fuzzy finding and grepping)
-- ---------------------------------------------------------------------------
local PLATFORM = OS .. "_" .. ARCH
local PORTABLE = {
  rg = {
    repo = "BurntSushi/ripgrep", pin = "14.1.1", tag = function(v) return v end,
    asset = function(v)
      local t = ({ linux_x64 = "x86_64-unknown-linux-musl", linux_arm64 = "aarch64-unknown-linux-gnu",
        mac_x64 = "x86_64-apple-darwin", mac_arm64 = "aarch64-apple-darwin", win_x64 = "x86_64-pc-windows-msvc" })[PLATFORM]
      return t and ("ripgrep-%s-%s.%s"):format(v, t, IS_WIN and "zip" or "tar.gz")
    end,
  },
  fd = {
    repo = "sharkdp/fd", pin = "10.2.0", tag = function(v) return "v" .. v end,
    asset = function(v)
      local t = ({ linux_x64 = "x86_64-unknown-linux-musl", linux_arm64 = "aarch64-unknown-linux-musl",
        mac_x64 = "x86_64-apple-darwin", mac_arm64 = "aarch64-apple-darwin", win_x64 = "x86_64-pc-windows-msvc" })[PLATFORM]
      return t and ("fd-v%s-%s.%s"):format(v, t, IS_WIN and "zip" or "tar.gz")
    end,
  },
  fzf = {
    repo = "junegunn/fzf", pin = "0.65.2", tag = function(v) return "v" .. v end,
    asset = function(v)
      local t = ({ linux_x64 = "linux_amd64", linux_arm64 = "linux_arm64", mac_x64 = "darwin_amd64",
        mac_arm64 = "darwin_arm64", win_x64 = "windows_amd64" })[PLATFORM]
      return t and ("fzf-%s-%s.%s"):format(v, t, IS_WIN and "zip" or "tar.gz")
    end,
  },
}

local function ensure_portable(name, cb)
  if exe(name) then return cb(true) end
  local spec = PORTABLE[name]
  once("portable:" .. name, function(done)
    busy(name, true)
    local function fetch(version, fallback)
      local asset = spec.asset(version)
      if not asset then busy(name, false); return done(false, name .. ": no build for " .. PLATFORM) end
      local url = ("%s/%s/releases/download/%s/%s"):format(SETTINGS.github, spec.repo, spec.tag(version), asset)
      local tmp = joinpath(DIR.dl, name .. "-unpack")
      download_and_extract(url, tmp, {}, function(ok, why)
        if not ok then
          if fallback then return fetch(fallback) end
          busy(name, false)
          return done(false, why)
        end
        local found = vim.fs.find(name .. EXE, { path = tmp, type = "file", limit = 1 })[1]
        if found then
          local target = joinpath(DIR.bin, name .. EXE)
          os.remove(target)
          uv.fs_rename(found, target)
          uv.fs_chmod(target, 493)   -- 0755
        end
        vim.fn.delete(tmp, "rf")
        busy(name, false)
        done(found ~= nil, not found and (name .. ": binary not found in archive") or nil)
      end)
    end
    github_latest(spec.repo, function(tag)
      local latest = tag and tag:gsub("^v", "")
      if latest and latest ~= spec.pin then fetch(latest, spec.pin) else fetch(spec.pin) end
    end)
  end, cb)
end

-- ---------------------------------------------------------------------------
-- 9d. Runtimes that tooling needs but your projects may not
-- ---------------------------------------------------------------------------
local function cmd_major_version(cmd, pattern)
  if not exe(cmd[1]) then return nil end
  local r = vim.system(cmd, { text = true }):wait()
  local out = (r.stdout or "") .. (r.stderr or "")
  return tonumber(out:match(pattern) or "")
end

-- Node.js — powers most web-flavoured language servers. A system Node of
-- version 18 or newer is used as is; otherwise a portable LTS build is
-- unpacked into the sandbox and put on PATH for this Neovim only.
local NODE_DIR = joinpath(DIR.runtimes, "node")
local NODE_BIN = IS_WIN and NODE_DIR or joinpath(NODE_DIR, "bin")
if vim.fn.executable(joinpath(NODE_BIN, "node" .. EXE)) == 1 then path_add(NODE_BIN, true) end

local function ensure_node(cb)
  local major = cmd_major_version({ "node", "--version" }, "^v(%d+)")
  if major and major >= 18 and exe("npm") then return cb(true) end
  once("runtime:node", function(done)
    busy("node", true)
    vim.system({ "curl", "-fsSL", SETTINGS.node_dist .. "/index.json" }, { text = true }, main(function(r)
      local ok, index = pcall(vim.json.decode, r.stdout or "")
      local version
      if ok and type(index) == "table" then
        for _, rel in ipairs(index) do
          if rel.lts then version = rel.version; break end
        end
      end
      local plat = ({ linux_x64 = "linux-x64", linux_arm64 = "linux-arm64", mac_x64 = "darwin-x64",
        mac_arm64 = "darwin-arm64", win_x64 = "win-x64" })[PLATFORM]
      if not version or not plat then
        busy("node", false)
        return done(false, "cannot reach " .. SETTINGS.node_dist .. " to fetch Node.js")
      end
      local url = ("%s/%s/node-%s-%s.%s"):format(SETTINGS.node_dist, version, version, plat, IS_WIN and "zip" or "tar.gz")
      download_and_extract(url, NODE_DIR, { strip = 1 }, function(okx, why)
        busy("node", false)
        if okx then path_add(NODE_BIN, true) end
        done(okx, why)
      end)
    end))
  end, cb)
end

-- JDK 21+ — jdtls refuses anything older. Your projects may still build with
-- Java 8 or 17: this JDK is handed to jdtls alone (via JAVA_HOME in its
-- environment) and never appears on your PATH.
local JDK_DIR = joinpath(DIR.runtimes, "jdk21")
local function jdk_home_from(dir)
  local home = OS == "mac" and joinpath(dir, "Contents", "Home") or dir
  return vim.fn.executable(joinpath(home, "bin", "java" .. EXE)) == 1 and home or nil
end
local function java_major(java)
  return cmd_major_version({ java, "-version" }, 'version "1%.(%d+)') -- 1.8 style
    or cmd_major_version({ java, "-version" }, 'version "(%d+)')
end

-- Find a usable JDK 21+ without downloading anything.
-- Returns found (boolean) and the JAVA_HOME to hand to jdtls (nil = PATH's java).
local function jdk21_local()
  local jh = vim.env.JAVA_HOME
  if jh and (java_major(joinpath(jh, "bin", "java" .. EXE)) or 0) >= 21 then return true, jh end
  local home = jdk_home_from(JDK_DIR)
  if home then return true, home end
  if (java_major("java") or 0) >= 21 then return true, nil end
  return false, nil
end

-- cb(ok, err, java_home)
local function ensure_jdk21(cb)
  local found, home = jdk21_local()
  if found then return cb(true, nil, home) end
  once("runtime:jdk21", function(done)
    busy("jdk21", true)
    local os_name = ({ linux = "linux", mac = "mac", win = "windows" })[OS]
    local url = ("%s/v3/binary/latest/21/ga/%s/%s/jdk/hotspot/normal/eclipse"):format(
      SETTINGS.adoptium_api, os_name, ARCH == "arm64" and "aarch64" or "x64")
    download_and_extract(url, JDK_DIR, { strip = 1, name = IS_WIN and "jdk21.zip" or "jdk21.tar.gz" }, function(ok, why)
      busy("jdk21", false)
      local h = ok and jdk_home_from(JDK_DIR) or nil
      if h then return done(true, nil, h) end
      done(false, why or "JDK 21 unpacked but no java binary inside")
    end)
  end, cb)
end

local function jdtls_env(java_home)
  if not java_home then return {} end
  return { cmd_env = {
    JAVA_HOME = java_home,
    PATH = joinpath(java_home, "bin") .. PATH_SEP .. (vim.env.PATH or ""),
  } }
end

-- Runtimes an installer needs. Toolchains you write code with (Go, Cargo,
-- PHP, Python) are yours to install; we only check for them.
local function ensure_runtime(need, cb)
  if not need then return cb(true) end
  if need == NODE then return ensure_node(cb) end
  if need == PY then
    if not python_cmd() then return cb(false, "Python 3 is not installed") end
    if OS == "linux" then return offer_sysdep("venv", cb) end
    return cb(true)
  end
  local bin = ({ go = "go", cargo = "cargo", php = "php" })[need]
  if exe(bin) then return cb(true) end
  cb(false, ("the %s toolchain is not installed"):format(bin))
end

-- ---------------------------------------------------------------------------
-- 9e. Mason — language servers, formatters and debug adapters
-- ---------------------------------------------------------------------------
local mason_refreshed, mason_offline = false, false
local function mason_registry(cb)
  local ok, reg = pcall(require, "mason-registry")
  if not ok then return cb(nil) end
  if mason_refreshed then return cb(reg) end
  once("mason:refresh", function(done)
    -- mason-registry is Mason's catalogue of packages; refresh() downloads
    -- the current one (from api.github.com) and calls back.
    reg.refresh(main(function(success)
      mason_refreshed = true
      mason_offline = not success
      done(reg)
    end))
  end, cb)
end

local function mason_install(name, cb)
  mason_registry(function(reg)
    if not reg then return cb(false, "mason.nvim is not available") end
    local ok, pkg = pcall(reg.get_package, name)
    if not ok then
      return cb(false, mason_offline
        and ("the Mason registry could not be downloaded (network or proxy?) — needed for " .. name)
        or ("unknown Mason package " .. name))
    end
    -- The LOCK names the version proven with this file; anything else is
    -- installed at Mason's latest and pinned by the next :IDEPin.
    local want = LOCK.tools[name]
    if pkg:is_installed() and (not want or pkg:get_installed_version() == want) then return cb(true) end
    once("mason:" .. name, function(done)
      busy(name, true)
      local function finish(success, err)
        busy(name, false)
        done(success, not success and (name .. ": " .. tostring(err)) or nil)
      end
      -- A Mason package is an object: pkg:install(opts, cb) installs it
      -- (opts.version picks a version), pkg:once(event, fn) waits for one
      -- that is already being installed.
      if pkg:is_installing() then
        pkg:once("install:success", main(function() finish(true) end))
        pkg:once("install:failed", main(function(e) finish(false, e) end))
      elseif want then
        pkg:install({ version = want }, main(function(success, result)
          if success then return finish(true) end
          -- The pinned version is gone from its source: take the latest and say so.
          notify(("%s %s is no longer available; installing the latest instead."):format(name, want), vim.log.levels.WARN)
          pkg:install({}, main(function(s2, r2) finish(s2, r2) end))
        end))
      else
        pkg:install({}, main(function(success, result) finish(success, result) end))
      end
    end, cb)
  end)
end

local function tool_ok(t)
  if not exe(t.bin) then return false end
  return not t.probe or t.probe()
end

local function ensure_tool(t, cb)
  if tool_ok(t) then return cb(true) end
  ensure_runtime(t.needs, function(ok, why)
    if not ok then return cb(false, t.bin .. ": " .. why) end
    mason_install(t.mason, function(installed, err)
      if installed then return cb(true) end
      -- Some Mason packages have no build for this machine (clangd on Linux
      -- arm64, for example): the system package manager is the fallback.
      if t.apt and OS == "linux" then
        SYSDEPS["pkg:" .. t.bin] = SYSDEPS["pkg:" .. t.bin] or
          { what = t.bin, ok = function() return exe(t.bin) end, apt = t.apt }
        return offer_sysdep("pkg:" .. t.bin, function(sys_ok) cb(sys_ok, not sys_ok and err or nil) end)
      end
      cb(false, err)
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- 9f. Tree-sitter parsers
-- ---------------------------------------------------------------------------
local function ts_installed()
  local ok, nts = pcall(require, "nvim-treesitter")
  if not ok then return {} end
  local set = {}
  for _, l in ipairs(nts.get_installed("parsers")) do set[l] = true end
  return set
end

-- Start Tree-sitter highlighting (and its experimental indent, when the
-- language has an indent query) for a buffer, if a parser is available.
local function ts_start(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local ft = vim.bo[buf].filetype
  local lang = vim.treesitter.language.get_lang(ft) or ft
  -- vim.treesitter.start(buf, lang): highlight this buffer from the parser's
  -- syntax tree (fails, harmlessly, when the parser is not installed).
  if not pcall(vim.treesitter.start, buf, lang) then return end
  if vim.treesitter.query.get(lang, "indents") and package.loaded["nvim-treesitter"] then
    -- 'indentexpr' is evaluated as Vimscript; v:lua.<expr> calls Lua from there.
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
end

-- Parsers from `langs` that nvim-treesitter offers but are not installed yet.
local ts_available
local function ts_missing(langs)
  local ok, nts = pcall(require, "nvim-treesitter")
  if not ok then return {} end
  if not ts_available then
    ts_available = {}
    for _, l in ipairs(nts.get_available()) do ts_available[l] = true end
  end
  local have, missing = ts_installed(), {}
  for _, l in ipairs(langs or {}) do
    if ts_available[l] and not have[l] then table.insert(missing, l) end
  end
  return missing
end

local function ensure_parsers(langs, cb)
  local ok, nts = pcall(require, "nvim-treesitter")
  if not ok then return cb(false, "nvim-treesitter is not available") end
  local missing = ts_missing(langs)
  if #missing == 0 then return cb(true) end
  offer_sysdep("cc", function(cc_ok, why)
    if not cc_ok then return cb(false, "parsers: " .. why) end
    ensure_tool({ bin = "tree-sitter", mason = "tree-sitter-cli" }, function(cli_ok, cli_why)
      if not cli_ok then return cb(false, "parsers: " .. tostring(cli_why)) end
      once("parsers:" .. table.concat(missing, ","), function(done)
        busy("parsers", true)
        -- The tree-sitter CLI keeps a lock directory under $XDG_CACHE_HOME;
        -- point it into the sandbox while it runs.
        local saved_cache = vim.env.XDG_CACHE_HOME
        vim.env.XDG_CACHE_HOME = DIR.xdg
        nts.install(missing):await(main(function(err, success)
          vim.env.XDG_CACHE_HOME = saved_cache
          busy("parsers", false)
          if not err and success ~= false then return done(true) end
          done(false, "parsers: " .. (err and tostring(err) or "download or build failed (details in :messages)"))
        end))
      end, cb)
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- 9g. Bringing a language to life
-- ---------------------------------------------------------------------------
local lsp_extra = {}   -- per-server config set at provisioning time (e.g. jdtls JAVA_HOME)

local function enable_servers(L)
  local enabled_any = false
  for _, server in ipairs(L.lsp) do
    local ready = true
    for _, t in ipairs(L.tools) do
      if t.server == server and not exe(t.bin) then ready = false end
    end
    -- vim.lsp.config(name, cfg) merges settings into a server's definition
    -- (nvim-lspconfig ships the defaults as lsp/<name>.lua); vim.lsp.enable(name)
    -- starts it automatically for every buffer of its filetypes.
    if ready and not vim.lsp.is_enabled(server) then
      if lsp_extra[server] then vim.lsp.config(server, lsp_extra[server]) end
      vim.lsp.enable(server)
      enabled_any = true
    end
  end
  if not enabled_any then return end
  -- vim.lsp.enable() attaches to already-open buffers only once startup is
  -- over; we may be called earlier, so knock on those buffers ourselves.
  local fts = {}
  for _, ft in ipairs(L.ft) do fts[ft] = true end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and fts[vim.bo[buf].filetype] then
      -- nvim_exec_autocmds fires an event by hand: here FileType, only for
      -- the autocmds vim.lsp.enable registered (group "nvim.lsp.enable").
      pcall(vim.api.nvim_exec_autocmds, "FileType", { group = "nvim.lsp.enable", buffer = buf })
    end
  end
end

local function restart_highlighting(L)
  local fts = {}
  for _, ft in ipairs(L.ft) do fts[ft] = true end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and fts[vim.bo[buf].filetype] then ts_start(buf) end
  end
end

-- Provision one language: parsers, tools, runtimes, then enable its servers.
-- Safe to call repeatedly; after the first success it is (nearly) free.
local function ensure_lang(id, opts)
  opts = opts or {}
  local L = LANGS[id]
  if not L or (P.ready[id] and not opts.force) then return end
  if not SETTINGS.auto_install and not opts.force then
    enable_servers(L)
    return
  end
  once("lang:" .. id, function(done)
    -- Fast path: everything already present (the common case after day one).
    local missing_tools = {}
    for _, t in ipairs(L.tools) do
      if not tool_ok(t) then table.insert(missing_tools, t) end
    end
    local missing_ts = #ts_missing(L.ts) > 0
    local need_jdk = false
    if L.jdk and not lsp_extra.jdtls then
      local found, home = jdk21_local()
      if found then lsp_extra.jdtls = jdtls_env(home) else need_jdk = true end
    end

    if #missing_tools == 0 and not missing_ts and not need_jdk then
      enable_servers(L)
      P.ready[id] = true
      return done(true)
    end

    notify(("Preparing %s tooling… (first use only)"):format(L.label))
    -- Two independent tracks: the language server starts the moment its
    -- tools are in place, without waiting for parsers to download and build.
    local jobs = {}
    for _, t in ipairs(missing_tools) do
      table.insert(jobs, function(cb) ensure_tool(t, cb) end)
    end
    if need_jdk then
      table.insert(jobs, function(cb)
        ensure_jdk21(function(ok, err, home)
          if ok then
            lsp_extra.jdtls = jdtls_env(home)
            return cb(true)
          end
          cb(false, "JDK 21: " .. tostring(err))
        end)
      end)
    end

    local tracks = {
      function(cb)
        all(jobs, function(results) vim.schedule(function() enable_servers(L); cb(true, results) end) end)
      end,
      function(cb)
        if not missing_ts then return cb(true, {}) end
        ensure_parsers(L.ts, function(ok, why)
          vim.schedule(function() restart_highlighting(L); cb(true, { { ok = ok, why = why } }) end)
        end)
      end,
    }

    -- `all` hands each track's second value back as `why`: here, its results.
    all(tracks, function(track_results)
      vim.schedule(function()
        local problems = {}
        for _, tr in ipairs(track_results) do
          for _, r in ipairs(tr.why or {}) do
            if not r.ok and r.why then table.insert(problems, r.why) end
          end
        end
        P.ready[id] = true
        P.failed[id] = #problems > 0 and problems or nil
        if #problems == 0 then
          notify(("%s is ready."):format(L.label))
        else
          -- One line only: a multi-line notice would trigger the hit-enter prompt.
          notify(("%s is partly ready (%d issue%s) — :IDEDoctor explains."):format(
            L.label, #problems, #problems > 1 and "s" or ""), vim.log.levels.WARN)
        end
        done(#problems == 0)
      end)
    end)
  end, opts.cb or function() end)
end

-- Every buffer that gets a filetype gets highlighting at once (when a parser
-- is already there) and, in the background, whatever else its language needs.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("super_ide_provision", { clear = true }),
  callback = function(ev)   -- ev.buf: the buffer; ev.match: its new filetype
    if vim.bo[ev.buf].buftype ~= "" then return end   -- "" = a normal file buffer
    local id = FT_LANG[ev.match]
    -- Scheduled so that ftplugin/indent scripts, which run after us, cannot
    -- overwrite the Tree-sitter indentexpr.
    vim.schedule(function()
      ts_start(ev.buf)
      if id then ensure_lang(id) end
    end)
  end,
})

-- fzf-lua drives the external program fzf. Normally :IDESync has fetched
-- it, but it can still be missing: a download that failed, or an init.lua
-- copied into place by hand, whose first start fetches it in the background
-- (just below). fzf-lua would then stop with a stack trace, so every
-- fuzzy-finder key goes through with_fzf: with fzf present it simply runs;
-- otherwise it says why in one line, starts or joins the download, and
-- reports once when that ends.
local fzf_waiting = false   -- a "ready / failed" report is already queued
local function with_fzf(fn)
  if exe("fzf") then return fn() end
  local running = inflight["portable:fzf"] ~= nil   -- see once(): keys of running jobs
  notify(running and "fzf is still downloading; try again in a moment."
    or "fzf is missing; downloading it now …", vim.log.levels.WARN)
  if fzf_waiting then return end
  fzf_waiting = true
  ensure_portable("fzf", function(ok)
    fzf_waiting = false
    if ok then notify("fzf is ready.")
    -- Kept to one line (no "Press ENTER" prompt); the cause is almost always
    -- the network, and the next press of the key simply tries again.
    else notify("fzf could not be downloaded; press the key again to retry.", vim.log.levels.ERROR) end
  end)
end
-- A key's right-hand side: run ":FzfLua <sub>" through the guard above.
local function fzf_cmd(sub)
  return function() with_fzf(function() vim.cmd("FzfLua " .. sub) end) end
end

-- Core command-line tools are fetched quietly shortly after startup.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    if not SETTINGS.auto_install or HEADLESS then return end
    vim.defer_fn(function()
      for name in pairs(PORTABLE) do ensure_portable(name, function() end) end
    end, 1500)
  end,
})

-- ============================================================================
-- 10. LSP — native vim.lsp.config / vim.lsp.enable on nvim-lspconfig's data
-- ============================================================================
-- nvim-lspconfig contributes only its lsp/*.lua definitions (commands, root
-- markers, settings). We override the few things that are a matter of taste.

-- How errors and warnings from language servers are shown (:help vim.diagnostic.config).
vim.diagnostic.config({
  severity_sort = true,
  virtual_text = { spacing = 2, source = "if_many" },
  float = { border = "rounded", source = "if_many" },
})

-- clangd keeps its project index in <root>/.cache/clangd. We redirect that
-- directory into the sandbox with a symlink (a junction on Windows) and hide
-- it from git through .git/info/exclude, which is never committed. Every
-- change is recorded so :IDEUninstall can put things back exactly.
local function git_exclude(root, rel_pattern)
  local top = vim.fs.root(root, ".git")
  if not top then return end
  local gitpath = joinpath(top, ".git")
  local st = uv.fs_stat(gitpath)
  if st and st.type == "file" then   -- worktree or submodule: ".git" points elsewhere
    local f = io.open(gitpath)
    local line = f and f:read("*l") or ""
    if f then f:close() end
    local dir = line:match("^gitdir:%s*(.-)%s*$")
    if not dir then return end
    if not dir:match("^/") and not dir:match("^%a:[/\\]") then dir = joinpath(top, dir) end
    gitpath = dir
  end
  local exclude = joinpath(gitpath, "info", "exclude")
  local sub = vim.fs.normalize(root):sub(#vim.fs.normalize(top) + 2)
  local pattern = "/" .. (sub ~= "" and (sub .. "/") or "") .. rel_pattern
  local f = io.open(exclude, "r")
  local content = f and f:read("*a") or ""
  if f then f:close() end
  for line in vim.gsplit(content, "\n", { plain = true }) do
    if line == pattern then return end
  end
  vim.fn.mkdir(vim.fs.dirname(exclude), "p")
  f = io.open(exclude, "a")
  if not f then return end
  f:write((content ~= "" and not content:match("\n$")) and "\n" or "", pattern, "\n")
  f:close()
  record("git-excludes.tsv", exclude, pattern)
end

local function clangd_link_cache(root)
  if not root or root == "" then return end
  root = vim.fs.normalize(root)
  local home = vim.fs.normalize(uv.os_homedir() or "")
  if root == home or root == "/" or root:match("^%a:/?$") then return end
  local link = joinpath(root, ".cache")
  -- fs_lstat looks at the link itself; fs_stat would follow it to its target.
  local st = uv.fs_lstat(link)
  if st then
    if st.type ~= "link" then git_exclude(root, ".cache/clangd/") end
    return   -- a real .cache already exists (or our link does): leave it be
  end
  local target = joinpath(DIR.clangd, vim.fn.sha256(root):sub(1, 16))
  vim.fn.mkdir(target, "p")
  -- dir/junction only matter on Windows, where a junction needs no admin rights.
  if uv.fs_symlink(target, link, { dir = true, junction = true }) then
    record("clangd-links.tsv", link, target)
    git_exclude(root, ".cache")   -- no trailing slash: to git a symlink is a file
  end
end

vim.lsp.config("clangd", {
  cmd = { "clangd", "--background-index", "--clang-tidy",
    "--completion-style=detailed", "--header-insertion=iwyu" },
  -- clangd stores the index of system headers under $XDG_CACHE_HOME.
  cmd_env = { XDG_CACHE_HOME = DIR.xdg },
  before_init = function(_, config) clangd_link_cache(config.root_dir) end,
})

vim.lsp.config("basedpyright", {
  settings = { basedpyright = { analysis = { typeCheckingMode = "standard" } } },
})

vim.lsp.config("lua_ls", {
  settings = { Lua = {
    runtime = { version = "LuaJIT" },
    diagnostics = { globals = { "vim" } },
    workspace = { checkThirdParty = false },
  } },
})

vim.lsp.config("html", { filetypes = { "html", "jsp" } })
vim.lsp.config("emmet_language_server", {
  filetypes = { "html", "jsp", "css", "scss", "less", "javascriptreact", "typescriptreact" },
})

-- Keymaps that only make sense with a language server attached.
local function first_supporting(bufnr, method)
  return #vim.lsp.get_clients({ bufnr = bufnr, method = method }) > 0
end

local function picker(name, fallback)
  return function()
    -- fzf-lua's list when it and the fzf program are both here, else Neovim's own.
    local ok, fzf = pcall(require, "fzf-lua")
    if ok and exe("fzf") then fzf[name]({ jump1 = true }) else fallback() end
  end
end

-- LspAttach fires each time a language server attaches to a buffer;
-- ev.data.client_id says which server. Mappings made with buffer = buf exist
-- in that buffer only, so they never shadow anything elsewhere.
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("super_ide_lsp", { clear = true }),
  callback = function(ev)
    local buf = ev.buf
    local function bmap(lhs, rhs, desc) map("n", lhs, rhs, { buffer = buf, desc = desc }) end

    bmap("gr", picker("lsp_references", vim.lsp.buf.references), "References")
    bmap("gy", function()
      if first_supporting(buf, "textDocument/typeDefinition") then
        picker("lsp_typedefs", vim.lsp.buf.type_definition)()
      else
        vim.lsp.buf.definition()
      end
    end, "Type definition (fallback: definition)")
    bmap("gI", function()
      if first_supporting(buf, "textDocument/implementation") then
        picker("lsp_implementations", vim.lsp.buf.implementation)()
      else
        vim.lsp.buf.definition()
      end
    end, "Implementation (fallback: definition)")
    bmap("[g", function() vim.diagnostic.jump({ count = -1, float = true }) end, "Previous diagnostic")
    bmap("]g", function() vim.diagnostic.jump({ count = 1, float = true }) end, "Next diagnostic")
    bmap("gl", vim.diagnostic.open_float, "Line diagnostics")
    bmap("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
    map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, { buffer = buf, desc = "Code action" })

    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.name == "clangd" then
      bmap("<leader>ch", function()
        -- client:request(method, params, handler, buf) sends one LSP request;
        -- switchSourceHeader is a clangd extension of the protocol.
        client:request("textDocument/switchSourceHeader", vim.lsp.util.make_text_document_params(buf),
          function(err, result)
            if err or not result then
              notify("clangd: no matching source/header found", vim.log.levels.WARN)
            else
              vim.cmd.edit(vim.uri_to_fname(result))
            end
          end, buf)
      end, "Switch source/header (clangd)")
    end
  end,
})

-- :LspInfo, a short name for the LSP health report.
-- A string instead of a function: the command runs that Ex command.
vim.api.nvim_create_user_command("LspInfo", "checkhealth vim.lsp", { desc = "LSP status" })

-- ============================================================================
-- 11. Run & debug
-- ============================================================================

-- <F6> runs the current file; <F7> runs the project around it. Both use a
-- floating terminal; press <Esc> then q to close it after the program ends.
-- Projects without a recognised build file fall back to running the file.
local function q(s) return vim.fn.shellescape(s) end
local CD = IS_WIN and "cd /d " or "cd "

local function compile_and_run(compiler, extra, file)
  local dir, name = vim.fs.dirname(file), vim.fs.basename(file)
  local stem = name:gsub("%.[^.]+$", "")
  local out = stem .. (IS_WIN and ".exe" or ".out")
  return ("%s%s && %s %s %s -o %s && %s"):format(CD, q(dir), compiler, q(name), extra, q(out),
    IS_WIN and q(out) or ("./" .. q(out)))
end

local RUN_FILE = {
  c      = function(f) return compile_and_run(exe("gcc") and "gcc" or "clang", "-O2 -Wall", f) end,
  cpp    = function(f) return compile_and_run(exe("g++") and "g++" or "clang++", "-std=c++20 -O2 -Wall", f) end,
  python = function(f) return (python_cmd() or "python3") .. " -u " .. q(f) end,
  rust   = function(f) return compile_and_run("rustc", "", f) end,
  go     = function(f) return "go run " .. q(f) end,
  java   = function(f) return "java " .. q(f) end,
  javascript = function(f) return "node " .. q(f) end,
  typescript = function(f) return "node " .. q(f) end,   -- Node 23+ strips types natively
  php    = function(f) return "php " .. q(f) end,
  lua    = function(f) return "nvim -l " .. q(f) end,
  sh     = function(f) return "sh " .. q(f) end,
  bash   = function(f) return "bash " .. q(f) end,
}

-- Project markers, most specific first.
local RUN_PROJECT = {
  { "Cargo.toml", "cargo run" },
  { "go.mod", "go run ." },
  { "CMakeLists.txt", "cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && cmake --build build" },
  { "Makefile", "make" }, { "makefile", "make" }, { "GNUmakefile", "make" },
  { "package.json", "npm start" },
  { "pom.xml", "mvn -q package" },
  { "build.gradle", IS_WIN and "gradlew.bat run" or "./gradlew run" },
  { "build.gradle.kts", IS_WIN and "gradlew.bat run" or "./gradlew run" },
}

local runner
local function run_in_terminal(cmd)
  local ok, Terminal = pcall(function() return require("toggleterm.terminal").Terminal end)
  if not ok then return vim.cmd("botright split | terminal " .. cmd) end
  if runner then pcall(function() runner:shutdown() end) end
  runner = Terminal:new({
    cmd = cmd, direction = "float", close_on_exit = false, hidden = true,
    -- Once the program ends, `q` in Normal mode closes the window.
    on_open = function(t) map("n", "q", function() t:close() end, { buffer = t.bufnr, nowait = true }) end,
  })
  runner:toggle()
end

local function run_file()
  vim.cmd("silent! write")
  local file = vim.api.nvim_buf_get_name(0)
  local build = RUN_FILE[vim.bo.filetype]
  if file == "" or not build then
    return notify("Don't know how to run filetype '" .. vim.bo.filetype .. "'.", vim.log.levels.WARN)
  end
  run_in_terminal(build(file))
end

local function run_project()
  vim.cmd("silent! wall")
  local file = vim.api.nvim_buf_get_name(0)
  local start = file ~= "" and vim.fs.dirname(file) or uv.cwd()
  local best_root, best_cmd
  for _, m in ipairs(RUN_PROJECT) do
    local root = vim.fs.root(start, m[1])
    -- Prefer the nearest root; markers earlier in the list win ties.
    if root and (not best_root or #root > #best_root) then best_root, best_cmd = root, m[2] end
  end
  if not best_root then return run_file() end
  run_in_terminal(CD .. q(best_root) .. " && " .. best_cmd)
end

map("n", "<F6>", run_file, { desc = "Run current file" })
map("n", "<F7>", run_project, { desc = "Run project" })

-- Debug adapters, fetched on the first <F5> in a language that has one.
local DAP = {
  codelldb = {
    mason = "codelldb",
    setup = function(dap)
      dap.adapters.codelldb = {
        type = "server", port = "${port}",
        executable = { command = vim.fn.exepath("codelldb"), args = { "--port", "${port}" }, detached = not IS_WIN },
      }
      local launch = {
        name = "Launch executable", type = "codelldb", request = "launch",
        program = function() return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/", "file") end,
        cwd = "${workspaceFolder}", stopOnEntry = false,
      }
      for _, ft in ipairs({ "c", "cpp", "rust" }) do
        dap.configurations[ft] = dap.configurations[ft] or { launch }
      end
    end,
  },
  debugpy = {
    mason = "debugpy", needs = PY,
    setup = function(dap)
      dap.adapters.python = { type = "executable", command = vim.fn.exepath("debugpy-adapter") }
      dap.configurations.python = dap.configurations.python or { {
        type = "python", request = "launch", name = "Launch file", program = "${file}",
        console = "integratedTerminal",
        pythonPath = function()
          local venv = vim.env.VIRTUAL_ENV or vim.fs.root(0, ".venv") and joinpath(vim.fs.root(0, ".venv"), ".venv")
          local py = venv and joinpath(venv, IS_WIN and "Scripts" or "bin", IS_WIN and "python.exe" or "python")
          return (py and exe(py)) and py or python_cmd()
        end,
      } }
    end,
  },
  delve = {
    mason = "delve", needs = GO,
    setup = function(dap)
      dap.adapters.delve = {
        type = "server", port = "${port}",
        executable = { command = vim.fn.exepath("dlv"), args = { "dap", "-l", "127.0.0.1:${port}" } },
      }
      dap.configurations.go = dap.configurations.go or {
        { type = "delve", name = "Debug package", request = "launch", program = "${fileDirname}" },
        { type = "delve", name = "Debug test", request = "launch", mode = "test", program = "${fileDirname}" },
      }
    end,
  },
}
local dap_ready = {}

local function dap_continue()
  local dap = require("dap")
  local L = lang_of(vim.bo.filetype)
  local id = L and L.dap
  if dap.session() or not id or dap_ready[id] then return dap.continue() end
  local spec = DAP[id]
  notify("Fetching the " .. id .. " debug adapter… (first use only)")
  ensure_runtime(spec.needs, function(ok, why)
    if not ok then return notify("Debugging needs more: " .. why, vim.log.levels.WARN) end
    mason_install(spec.mason, function(installed, err)
      vim.schedule(function()
        if not installed then return notify("Debug adapter: " .. tostring(err), vim.log.levels.ERROR) end
        spec.setup(dap)
        dap_ready[id] = true
        dap.continue()
      end)
    end)
  end)
end

-- ============================================================================
-- 12. Plugins
-- ============================================================================
local lazypath = joinpath(DIR.data, "lazy", "lazy.nvim")

-- lazy.nvim manages every plugin but itself: it is cloned here and held at
-- the LOCK's commit by hand (it will not move its own checkout while running).
local function pin_lazy_self()
  local want = (LOCK.plugins["lazy.nvim"] or {}).commit
  if not want then return end
  local head = vim.system({ "git", "-C", lazypath, "rev-parse", "HEAD" }, { text = true }):wait()
  if vim.trim(head.stdout or "") == want then return end
  if vim.system({ "git", "-C", lazypath, "checkout", "-q", want }):wait().code ~= 0 then
    vim.system({ "git", "-C", lazypath, "fetch", "-q", "origin" }):wait()
    vim.system({ "git", "-C", lazypath, "checkout", "-q", want }):wait()
  end
end

if not uv.fs_stat(lazypath) then
  local r = vim.system({ "git", "clone", "--filter=blob:none",
    SETTINGS.github .. "/folke/lazy.nvim.git", lazypath }):wait()
  if r.code ~= 0 then
    vim.api.nvim_echo({ { "Super IDE: cloning lazy.nvim failed — is git installed and GitHub reachable?\n"
      .. (r.stderr or ""), "ErrorMsg" } }, true, {})
    return
  end
  pin_lazy_self()
end
-- 'runtimepath' (rtp) is the list of directories Neovim loads plugins and
-- Lua modules from; lazy.nvim must be on it before require("lazy") works.
vim.opt.rtp:prepend(lazypath)

-- Statusline component: what is being fetched right now.
local function provisioning_status()
  local names = vim.tbl_keys(P.busy)
  if #names == 0 then return "" end
  table.sort(names)
  return "⟳ " .. table.concat(names, " ")
end

-- Each entry is a lazy.nvim "spec": a table describing one plugin.
--   [1] "owner/repo"  the GitHub repository (url = "..." for anywhere else)
--   lazy = false      load at start-up; most plugins load on first need instead:
--   event = "..."     ... when that autocmd event fires (VeryLazy: just after start-up)
--   cmd / ft / keys   ... when the command runs, the filetype opens, the key is pressed
--                         (keys entries are also mappings: { lhs, rhs, desc = ... })
--   dependencies      plugins loaded before this one
--   opts = { ... }    lazy.nvim calls require("<main module>").setup(opts)
--   config = fn       or call setup yourself, for anything opts cannot say
--   enabled = bool    false: declared but not installed or loaded
--   priority          load order among start-up plugins (colour schemes first)
-- Versions are not written here: the LOCK pins each plugin's commit.
local plugins = {
  -- Look & feel ------------------------------------------------------------
  {
    "Tsuzat/NeoSolarized.nvim", lazy = false, priority = 1000,
    config = function()
      require("NeoSolarized").setup({
        style = "dark", transparent = false, terminal_colors = true, enable_italics = true,
      })
      vim.o.background = "dark"
      vim.cmd.colorscheme("NeoSolarized")
    end,
  },
  { "nvim-tree/nvim-web-devicons", lazy = true },
  {
    "nvim-lualine/lualine.nvim", event = "VeryLazy",
    opts = {
      options = { theme = "solarized_dark", globalstatus = true },
      sections = { lualine_x = { provisioning_status, "encoding", "fileformat", "filetype" } },
    },
  },
  {
    "folke/which-key.nvim", event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>c", group = "code / guides" }, { "<leader>d", group = "debug" },
        { "<leader>f", group = "find / format" }, { "<leader>i", group = "indent" },
        { "<leader>n", group = "neogen docs" }, { "<leader>q", group = "session" },
        { "<leader>r", group = "rename / grep" }, { "<leader>t", group = "toggle" },
      },
    },
  },
  {
    "lukas-reineke/indent-blankline.nvim", main = "ibl", event = { "BufReadPost", "BufNewFile" },
    opts = {
      indent = { char = "│", tab_char = "│" },
      scope = { enabled = true, show_start = false, show_end = false },
      exclude = { filetypes = { "help", "superide", "neo-tree", "lazy", "mason", "toggleterm", "fzf" } },
    },
    config = function(_, opts)
      -- Borrow existing colours rather than hard-coding any.
      vim.api.nvim_set_hl(0, "IblIndent", { link = "Comment" })
      vim.api.nvim_set_hl(0, "IblScope", { link = "Function" })
      require("ibl").setup(opts)
    end,
    keys = { { "<leader>ig", "<cmd>IBLToggle<CR>", desc = "Indent guides toggle" } },
  },
  {
    "HiPhish/rainbow-delimiters.nvim", event = { "BufReadPost", "BufNewFile" },
    submodules = false,   -- its only submodule is a test harness hosted off GitHub
    config = function()
      local function link()
        for from, to in pairs({
          RainbowDelimiterRed = "Identifier", RainbowDelimiterYellow = "Function",
          RainbowDelimiterBlue = "Type", RainbowDelimiterOrange = "Statement",
          RainbowDelimiterGreen = "Constant", RainbowDelimiterViolet = "PreProc",
          RainbowDelimiterCyan = "Special",
        }) do vim.api.nvim_set_hl(0, from, { link = to }) end
      end
      link()
      vim.api.nvim_create_autocmd("ColorScheme", { callback = link })
    end,
  },

  -- Finding & exploring -----------------------------------------------------
  {
    "ibhagwan/fzf-lua", cmd = "FzfLua",
    opts = function()
      -- Patch debris never belongs in a file list.
      local skip_fd = " --exclude '*.patch' --exclude '*.diff' --exclude '*.rej' --exclude '*.orig'"
      local skip_rg = " -g '!*.patch' -g '!*.diff' -g '!*.rej' -g '!*.orig'"
      return {
        files = {
          fd_opts = "--color=never --type f --type l --hidden --follow --exclude .git" .. skip_fd,
          rg_opts = "--color=never --files --hidden --follow -g '!.git'" .. skip_rg,
        },
      }
    end,
    keys = {
      -- fzf_cmd (section 9): runs :FzfLua only once the fzf program is here.
      { "<C-p>", fzf_cmd("files"), desc = "Find files" },
      { "<leader>ff", fzf_cmd("files"), desc = "Find files" },
      { "<leader>fb", fzf_cmd("buffers"), desc = "Buffers" },
      { "<leader>fh", fzf_cmd("helptags"), desc = "Help tags" },
      { "<leader>fo", fzf_cmd("oldfiles"), desc = "Recent files" },
      { "<leader>rg", fzf_cmd("live_grep"), desc = "Live grep" },
    },
  },
  {
    "nvim-neo-tree/neo-tree.nvim", branch = "v3.x", cmd = "Neotree",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons", "MunifTanjim/nui.nvim" },
    opts = {
      close_if_last_window = true,
      -- The NERDTreeQuitOnOpen habit: the tree steps aside once a file is chosen.
      event_handlers = { {
        event = "file_opened",
        handler = function() require("neo-tree.command").execute({ action = "close" }) end,
      } },
      filesystem = { follow_current_file = { enabled = true }, use_libuv_file_watcher = true },
      window = { width = 34 },
    },
    keys = { { "<leader>e", "<cmd>Neotree toggle<CR>", desc = "Explorer (neo-tree)" } },
  },
  {
    "stevearc/oil.nvim", lazy = false,   -- lazy=false so `nvim some/dir` opens Oil
    opts = {},
    keys = { { "-", "<cmd>Oil<CR>", desc = "Oil (parent directory)" } },
  },
  {
    "hedyhli/outline.nvim", cmd = "Outline", opts = {},
    keys = { { "<leader>o", "<cmd>Outline<CR>", desc = "Outline (symbols)" } },
  },

  -- Language intelligence ---------------------------------------------------
  { "neovim/nvim-lspconfig", lazy = false },   -- provides lsp/*.lua definitions only
  {
    "mason-org/mason.nvim", lazy = false,
    opts = {
      PATH = "append",   -- a tool you installed yourself always takes precedence
      ui = { border = "rounded" },
      github = { download_url_template = SETTINGS.github .. "/%s/releases/download/%s/%s" },
    },
  },
  { "nvim-treesitter/nvim-treesitter", branch = "main", lazy = false, build = ":TSUpdate" },
  {
    "saghen/blink.cmp", version = "1.*", lazy = false,   -- loaded early: it registers LSP capabilities
    dependencies = { "rafamadriz/friendly-snippets", { "L3MON4D3/LuaSnip", version = "v2.*" } },
    config = function()
      local ls = require("luasnip")
      require("luasnip.loaders.from_vscode").lazy_load()
      -- File header template for C/C++/assembly: type `filehdr`, accept it.
      local filehdr = ls.parser.parse_snippet("filehdr", table.concat({
        "/*", " * File: ${1:FILE_NAME}", " * Brief: ${2:WHAT_THIS_FILE_DOES}", " * Author: ${3:YOUR_NAME}",
        " * Version: ${4:0.1}", " * License: ${5:LICENSE}", " * Created: ${6:YYYY-MM-DD}", " */", "", "${0}",
      }, "\n"))
      for _, ft in ipairs({ "c", "cpp", "asm" }) do ls.add_snippets(ft, { filehdr }) end

      require("blink.cmp").setup({
        snippets = { preset = "luasnip" },
        -- Completion keys: <Tab>/<S-Tab> and the arrows select an item (in a
        -- snippet, <Tab>/<S-Tab> jump between its fields); <CR> accepts only
        -- an item selected that way. Nothing is preselected, so <CR> with no
        -- selection is a plain newline: a word is never inserted unseen.
        keymap = {
          preset = "none",
          ["<CR>"]      = { "accept", "fallback" },
          ["<Tab>"]     = { "select_next", "snippet_forward", "fallback" },
          ["<S-Tab>"]   = { "select_prev", "snippet_backward", "fallback" },
          ["<Down>"]    = { "select_next", "fallback" },
          ["<Up>"]      = { "select_prev", "fallback" },
          ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
          ["<C-e>"]     = { "cancel", "fallback" },
          ["<C-b>"]     = { "scroll_documentation_up", "fallback" },
          ["<C-f>"]     = { "scroll_documentation_down", "fallback" },
          ["<C-k>"]     = { "show_signature", "hide_signature", "fallback" },
        },
        completion = {
          list = { selection = { preselect = false, auto_insert = false } },
          documentation = { auto_show = true, auto_show_delay_ms = 300 },
        },
        signature = { enabled = true },
        sources = { default = { "lsp", "path", "snippets", "buffer" } },
        fuzzy = { implementation = "prefer_rust_with_warning" },
      })
    end,
  },
  {
    "stevearc/conform.nvim", event = "BufWritePre", cmd = "ConformInfo",
    opts = function()
      local by_ft = {}
      for _, L in pairs(LANGS) do
        for ft, list in pairs(L.format) do
          local entry = { unpack(list) }
          if list.stop then entry.stop_after_first = true end
          by_ft[ft] = entry
        end
      end
      vim.g.format_on_save = SETTINGS.format_on_save
      return {
        formatters_by_ft = by_ft,
        default_format_opts = { lsp_format = "fallback" },
        format_on_save = function()
          if vim.g.format_on_save then return { timeout_ms = 2000 } end
        end,
      }
    end,
    keys = {
      { "<leader>f", function() require("conform").format({ timeout_ms = 2000 }) end, desc = "Format buffer" },
      { "<leader>tf", function()
        vim.g.format_on_save = not vim.g.format_on_save
        notify("Format on save: " .. (vim.g.format_on_save and "ON" or "OFF"))
      end, desc = "Toggle format-on-save" },
    },
  },
  {
    "danymat/neogen", cmd = "Neogen",
    opts = { snippet_engine = "luasnip" },
    keys = {
      { "<leader>ng", function() require("neogen").generate() end, desc = "Neogen: document symbol" },
      { "<leader>nf", function() require("neogen").generate({ type = "file" }) end, desc = "Neogen: file header" },
    },
  },
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = { check_ts = false, disable_filetype = { "fzf", "vim" } } },
  { "kylechui/nvim-surround", event = "VeryLazy", opts = {} },

  -- Terminal, git, sessions ---------------------------------------------------
  {
    "akinsho/toggleterm.nvim", version = "*", event = "VeryLazy",
    opts = { open_mapping = [[<C-\>]], direction = "float", start_in_insert = true, shade_terminals = true },
  },
  { "tpope/vim-fugitive", cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit", "Gread", "Gwrite", "Gblame" } },
  { "lewis6991/gitsigns.nvim", event = { "BufReadPre", "BufNewFile" }, opts = {} },
  {
    "folke/persistence.nvim", event = "BufReadPre", opts = {},
    keys = {
      { "<leader>qs", function() require("persistence").load() end, desc = "Restore session (this directory)" },
      { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Restore last session" },
    },
  },

  -- Debugging (adapters are fetched on the first <F5>) -------------------------
  {
    "rcarriga/nvim-dap-ui", enabled = SETTINGS.debug,
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup()
      dap.listeners.after.event_initialized.super_ide = function() dapui.open() end
      dap.listeners.before.event_terminated.super_ide = function() dapui.close() end
      dap.listeners.before.event_exited.super_ide = function() dapui.close() end
    end,
    keys = {
      { "<F5>", dap_continue, desc = "Debug: continue / start" },
      { "<F9>", function() require("dap").toggle_breakpoint() end, desc = "Debug: toggle breakpoint" },
      { "<F10>", function() require("dap").step_over() end, desc = "Debug: step over" },
      { "<F11>", function() require("dap").step_into() end, desc = "Debug: step into" },
      { "<F12>", function() require("dap").step_out() end, desc = "Debug: step out" },
      { "<leader>db", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end,
        desc = "Debug: conditional breakpoint" },
      { "<leader>dr", function() require("dap").repl.toggle() end, desc = "Debug: REPL" },
      { "<leader>du", function() require("dapui").toggle() end, desc = "Debug: UI toggle" },
    },
  },

  -- Your plugins -------------------------------------------------------------
  -- :IDEAdd owner/repo writes new specs between the two markers below (keep
  -- them); you may write here by hand as well. A new plugin is installed at its
  -- newest commit and enters the LOCK with the next :IDEPin.
  -- @@PLUGINS BEGIN
  -- @@PLUGINS END
}

-- lazy.nvim reads plugin versions from a lockfile; ours is written from the
-- LOCK table (installer, :IDESwitch), and lazy keeps it current afterwards.
if not uv.fs_stat(FILE.lockfile) then LC.json_write(FILE.lockfile, LOCK.plugins) end

-- Hand every spec to lazy.nvim: it installs what is missing (at the
-- lockfile's commits) and loads each plugin at the moment its spec names.
require("lazy").setup(plugins, {
  lockfile = FILE.lockfile,
  ui = { border = "rounded" },
  git = { url_format = SETTINGS.github .. "/%s.git", timeout = 300 },
  rocks = { enabled = false },   -- no luarocks needed; also silences :checkhealth
  change_detection = { notify = false },
  install = { colorscheme = { "NeoSolarized", "habamax" } },
  performance = { rtp = { disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" } } },
})

-- nvim-treesitter puts its parser directory on 'runtimepath' when set up;
-- do it now so parsers installed in earlier sessions are found at once.
pcall(function() require("nvim-treesitter").setup({}) end)

-- Undo tree: Neovim 0.12 ships one; no plugin required.
map("n", "<leader>u", function()
  vim.cmd.packadd("nvim.undotree")
  require("undotree").open()
end, { desc = "UndoTree" })

-- ============================================================================
-- 13. Dashboard — a hexagram drawn in plain ASCII, so it survives any terminal
-- ============================================================================
-- Two interlocking triangles, generated rather than pasted: the upward one in
-- one colour, the downward one in another, the title in the hexagon between.
local function hexagram(n, title1, title2)
  -- n: rows per triangle (a multiple of 3 keeps the star symmetric)
  local k = n / 3                       -- the downward triangle starts k rows lower
  local c0 = n + 1                      -- apex column of the upward triangle
  local rows, width = n + k, 2 * n + 2
  local grid = {}
  for r = 0, rows - 1 do
    grid[r] = {}
    for c = 0, width - 1 do grid[r][c] = { " ", nil } end
  end
  local function put(r, c, ch, hl)
    if grid[r] and grid[r][c] and grid[r][c][1] == " " then grid[r][c] = { ch, hl } end
  end
  for r = 0, n - 1 do                    -- upward triangle
    put(r, c0 - r, "/", "SuperIdeUp")
    put(r, c0 + 1 + r, "\\", "SuperIdeUp")
  end
  for r = k, k + n - 1 do                -- downward triangle
    put(r, (c0 - n + 1) + (r - k), "\\", "SuperIdeDown")
    put(r, (c0 + n) - (r - k), "/", "SuperIdeDown")
  end
  for c = c0 - n + 2, c0 + n - 1 do put(n - 1, c, "_", "SuperIdeUp") end   -- upward base
  for c = c0 - n + 1, c0 + n do put(k - 1, c, "_", "SuperIdeDown") end     -- downward top
  local mid = math.floor((n - 1 + k) / 2)   -- the widest rows of the hexagon
  for i, text in ipairs({ title1, title2 }) do
    local start = c0 - math.floor((#text - 1) / 2)
    for j = 1, #text do grid[mid + i - 1][start + j - 1] = { text:sub(j, j), "SuperIdeTitle" } end
  end
  local lines, hls = {}, {}
  for r = 0, rows - 1 do
    local chars = {}
    for c = 0, width - 1 do
      chars[#chars + 1] = grid[r][c][1]
      if grid[r][c][2] then table.insert(hls, { r, c, grid[r][c][2] }) end
    end
    lines[#lines + 1] = (table.concat(chars):gsub("%s+$", ""))
  end
  return lines, hls, width
end

local DASH_ITEMS = {
  { "f", "Find file", "FzfLua files" }, { "r", "Recent files", "FzfLua oldfiles" },
  { "g", "Grep text", "FzfLua live_grep" }, { "s", "Restore session", "lua require('persistence').load()" },
  { "e", "File explorer", "Neotree toggle" }, { "c", "Edit config", "edit $MYVIMRC" },
  { "d", "IDE doctor", "IDEDoctor" }, { "u", "Plugins", "Lazy" }, { "q", "Quit", "qa" },
}

-- A namespace groups highlights (extmarks) so they can be cleared together.
local dash = { buf = nil, ns = vim.api.nvim_create_namespace("super_ide_dashboard") }

local function dash_highlights()
  -- default = true: only if the colour scheme has not defined the group itself.
  vim.api.nvim_set_hl(0, "SuperIdeUp", { link = "Function", default = true })
  vim.api.nvim_set_hl(0, "SuperIdeDown", { link = "Statement", default = true })
  vim.api.nvim_set_hl(0, "SuperIdeTitle", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "SuperIdeKey", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "SuperIdeFooter", { link = "Comment", default = true })
end

local function dash_render()
  local buf = dash.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return end
  local W, H = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)

  local art, art_hls, art_w = hexagram(12, "Neovim", "Super IDE")
  local menu = {}
  for i = 1, #DASH_ITEMS, 3 do
    local row = {}
    for j = i, math.min(i + 2, #DASH_ITEMS) do
      row[#row + 1] = ("%s  %-15s"):format(DASH_ITEMS[j][1], DASH_ITEMS[j][2])
    end
    menu[#menu + 1] = (table.concat(row, "  "):gsub("%s+$", ""))
  end
  local stats = (function()
    local ok, lazy = pcall(require, "lazy")
    local v = vim.version()
    local s = ("Neovim %d.%d.%d"):format(v.major, v.minor, v.patch)
    if ok then
      local st = lazy.stats()
      s = s .. (" · %d plugins"):format(st.count)
      if st.startuptime and st.startuptime > 0 then s = s .. (" · started in %d ms"):format(math.floor(st.startuptime + 0.5)) end
    end
    return s
  end)()

  local show_art = H >= #art + #menu + 6 and W >= art_w + 2
  local body, kinds = {}, {}
  if show_art then
    for _, l in ipairs(art) do body[#body + 1] = l; kinds[#kinds + 1] = "art" end
    body[#body + 1] = ""; kinds[#kinds + 1] = ""
  end
  for _, l in ipairs(menu) do body[#body + 1] = l; kinds[#kinds + 1] = "menu" end
  body[#body + 1] = ""; kinds[#kinds + 1] = ""
  body[#body + 1] = stats; kinds[#kinds + 1] = "footer"

  local top = math.max(0, math.floor((H - #body) / 2))
  local lines, pads = {}, {}
  for _ = 1, top do lines[#lines + 1] = "" end
  local block_w = 0
  for i, l in ipairs(body) do
    if kinds[i] ~= "footer" then block_w = math.max(block_w, vim.fn.strdisplaywidth(l)) end
  end
  if show_art then block_w = math.max(block_w, art_w) end
  for i, l in ipairs(body) do
    local w = kinds[i] == "art" and art_w or (kinds[i] == "menu" and block_w or vim.fn.strdisplaywidth(l))
    local pad = math.max(0, math.floor((W - w) / 2))
    pads[i] = pad
    lines[#lines + 1] = string.rep(" ", pad) .. l
  end

  vim.bo[buf].modifiable = true
  -- set_lines(buf, start, end, strict, lines): 0..-1 replaces the whole buffer.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, dash.ns, 0, -1)
  local function hl(row, col_s, col_e, group)
    -- An extmark colours a span (row, col_s .. end_col) without touching the text.
    vim.api.nvim_buf_set_extmark(buf, dash.ns, row, col_s, { end_col = col_e, hl_group = group })
  end
  for i, kind in ipairs(kinds) do
    local row = top + i - 1
    if kind == "menu" then
      local text = body[i]
      local s = 1
      while true do
        local a, b = text:find("%f[%w]%w%f[%W]  ", s)
        if not a then break end
        hl(row, pads[i] + a - 1, pads[i] + a, "SuperIdeKey")
        s = b + 1
      end
    elseif kind == "footer" then
      hl(row, pads[i], pads[i] + #body[i], "SuperIdeFooter")
    end
  end
  if show_art then
    for _, h in ipairs(art_hls) do hl(top + h[1], pads[1] + h[2], pads[1] + h[2] + 1, h[3]) end
  end
end

local function dash_open()
  -- Only for a bare `nvim`: no file arguments, no piped input, nothing typed.
  if vim.fn.argc() > 0 or vim.g.super_ide_stdin or HEADLESS then return end
  local cur = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(cur) ~= "" or vim.bo[cur].modified
    or vim.api.nvim_buf_line_count(cur) > 1 or #(vim.api.nvim_buf_get_lines(cur, 0, 1, false)[1] or "") > 0 then
    return
  end
  dash_highlights()
  local buf = vim.api.nvim_create_buf(false, true)
  dash.buf = buf
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "superide"
  vim.api.nvim_win_set_buf(0, buf)
  local win = vim.api.nvim_get_current_win()
  -- [0]: options local to this buffer-in-window; the next file gets the defaults back.
  for opt, val in pairs({ number = false, relativenumber = false, cursorline = false, cursorcolumn = false,
    colorcolumn = "", signcolumn = "no", list = false, foldcolumn = "0", spell = false, wrap = false }) do
    vim.wo[win][0][opt] = val
  end
  if vim.api.nvim_buf_is_valid(cur) and cur ~= buf then pcall(vim.api.nvim_buf_delete, cur, {}) end
  for _, item in ipairs(DASH_ITEMS) do
    -- Fuzzy-finder items go through the fzf guard (section 9), like their keys.
    local sub = item[3]:match("^FzfLua (%S+)$")
    map("n", item[1], sub and fzf_cmd(sub) or ("<cmd>" .. item[3] .. "<CR>"), { buffer = buf, nowait = true, desc = item[2] })
  end
  dash_render()
  local g = vim.api.nvim_create_augroup("super_ide_dashboard", { clear = true })
  -- The terminal may report its real size only after VimEnter; redraw then too.
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized", "UIEnter" }, { group = g, callback = dash_render })
  vim.defer_fn(dash_render, 50)
  vim.api.nvim_create_autocmd("User", { group = g, pattern = "VeryLazy", callback = dash_render })
  vim.api.nvim_create_autocmd("ColorScheme", { group = g, callback = function() dash_highlights(); dash_render() end })
  vim.api.nvim_create_autocmd("BufWipeout", { group = g, buffer = buf, callback = function()
    dash.buf = nil
    pcall(vim.api.nvim_del_augroup_by_id, g)
  end })
end

-- `cmd | nvim -` reads stdin: remember it, so the start screen stays away.
vim.api.nvim_create_autocmd("StdinReadPre", { callback = function() vim.g.super_ide_stdin = true end })
vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = dash_open })

-- ============================================================================
-- 14. Commands
-- ============================================================================

-- :IDEInstall [lang ...|all] — provision now instead of waiting to meet a file.
local function lang_ids(args)
  if #args == 0 then
    local id = FT_LANG[vim.bo.filetype]
    return id and { id } or {}
  end
  if args[1] == "all" then return vim.tbl_keys(LANGS) end
  local ids = {}
  for _, a in ipairs(args) do
    local id = LANGS[a] and a or FT_LANG[a]
    if id then ids[#ids + 1] = id else notify("Unknown language: " .. a, vim.log.levels.WARN) end
  end
  return ids
end

-- In headless runs (:IDESync from the installer) we wait until everything settles.
local function wait_until_idle(timeout_ms)
  if not HEADLESS then return end
  -- vim.wait keeps the event loop running (so downloads and callbacks make
  -- progress) until no job is in flight, checking every 500 ms.
  vim.wait(timeout_ms or 20 * 60 * 1000, function()
    return next(inflight) == nil
  end, 500)
end

local function provision(ids)
  P.offered = {}
  for _, id in ipairs(ids) do
    P.ready[id] = nil
    ensure_lang(id, { force = true })
  end
  wait_until_idle()
end

-- nvim_create_user_command(name, fn, opts) defines :IDEInstall. Name must
-- start with a capital letter. fn(cmd) runs on each use: cmd.fargs is the
-- argument list ({ "python", "rust" }). nargs = "*": any number of arguments.
-- complete = a function returning the words <Tab> may offer.
vim.api.nvim_create_user_command("IDEInstall", function(cmd)
  provision(lang_ids(cmd.fargs))
end, {
  nargs = "*", desc = "Provision language tooling now",
  complete = function() return vim.list_extend({ "all" }, vim.tbl_keys(LANGS)) end,
})

-- :IDEPrewarm [dir] — scan a project and provision every language it contains.
vim.api.nvim_create_user_command("IDEPrewarm", function(cmd)
  local root = vim.fs.normalize(vim.fn.fnamemodify(cmd.args ~= "" and cmd.args or ".", ":p"))
  local seen, count = {}, 0
  local skip = { [".git"] = true, node_modules = true, [".cache"] = true, build = true, target = true, [".venv"] = true }
  -- vim.fs.dir walks a tree: yields (relative name, "file" | "directory" | ...);
  -- skip(dir) returning false keeps it from descending into that directory.
  for name, kind in vim.fs.dir(root, { depth = 6, skip = function(dir) return not skip[vim.fs.basename(dir)] end }) do
    if kind == "file" then
      count = count + 1
      local ft = vim.filetype.match({ filename = joinpath(root, name) })
      local id = ft and FT_LANG[ft]
      if id then seen[id] = true end
      if count > 20000 then break end
    end
  end
  local ids = vim.tbl_keys(seen)
  table.sort(ids)
  notify(("Prewarming %d language(s) found in %s: %s"):format(#ids, root, table.concat(ids, ", ")))
  if HEADLESS then
    for name in pairs(PORTABLE) do ensure_portable(name, function() end) end
  end
  provision(ids)
end, { nargs = "?", complete = "dir", desc = "Provision every language found in a directory" })
-- nargs = "?": zero or one argument; complete = "dir": <Tab> completes directories.

-- ---------------------------------------------------------------------------
-- 14a. Generations — what is live, and how it compares with the LOCK
-- ---------------------------------------------------------------------------
local function installed_tools()   -- Mason package -> installed version
  local ok, reg = pcall(require, "mason-registry")
  if not ok then return nil end
  local t = {}
  for _, pkg in ipairs(reg.get_installed_packages()) do t[pkg.name] = pkg:get_installed_version() or "?" end
  return t
end

-- `git -C dir args…`, its output lines; nil when git fails (e.g. a commit that
-- is not in the local history).
local function git_lines(dir, args)
  local r = vim.system(vim.list_extend({ "git", "-C", dir }, args), { text = true }):wait()
  if r.code ~= 0 then return nil end
  return vim.split(vim.trim(r.stdout), "\n", { trimempty = true })
end

-- A language is "in use" once its parsers or Mason tools are on disk.
local function used_langs(tools)
  local have_ts, out = ts_installed(), {}
  for id, L in pairs(LANGS) do
    local used = false
    for _, l in ipairs(L.ts) do if have_ts[l] then used = true end end
    for _, t in ipairs(L.tools) do if t.mason and (tools or {})[t.mason] then used = true end end
    if used then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

-- lazy.nvim rewrites its lockfile only after its own operations (install,
-- update, clean, ...). Right after you delete a plugin's spec, the file still
-- names that plugin, and a :IDEPin reading it would write the deleted plugin
-- back into the LOCK. So rewrite the file first from the live truth:
-- lazy.manage.lock.update() (a lazy.nvim internal) records every plugin that is
-- declared now and installed, at the commit actually checked out.
local function refresh_lockfile()
  local ok, lock = pcall(require, "lazy.manage.lock")   -- pcall: lazy may be missing
  if ok then pcall(lock.update) end
end

-- Plugin directories still on disk but no longer declared. lazy.nvim lists
-- them in Config.to_clean when it reads the specs; :IDESync deletes them.
local function undeclared_plugins()
  local ok, cfg = pcall(require, "lazy.core.config")
  return ok and #(cfg.to_clean or {}) or 0
end

-- What is running right now, in LOCK form.
local function live_lock()
  refresh_lockfile()   -- see above: never trust a stale lockfile
  local tools = installed_tools() or {}
  return {
    pinned = os.date("%Y-%m-%d %H:%M"),
    neovim = LC.running_tag(),
    plugins = LC.json_read(FILE.lockfile) or {},
    tools = tools,
    langs = used_langs(tools),
  }
end

-- "pinned", "modified" or "candidate", with the reasons.
local function generation_state()
  local cand = LC.json_read(FILE.candidate)
  if cand then
    -- scope: "all" (--all), "selected" (chosen in the checklist), "neovim"
    -- (:IDEUpdate vX.Y.Z).
    local nvim = cand.new ~= cand.prev and (", Neovim %s → %s"):format(cand.prev or "?", cand.new or "?") or ""
    return "candidate", { cand.scope == "neovim" and ("trying Neovim %s; was %s"):format(cand.new or "?", cand.prev or "?")
      or ("trying %s update(s)%s"):format(cand.scope == "all" and ("all " .. (cand.count or "")) or (cand.count or "?") .. " selected", nvim) }
  end
  local why = {}
  local gen = LC.gen_current()
  if not gen then
    why[#why + 1] = "no generation stored yet (install with `nvim -l init.lua install`, or :IDEPin)"
  elseif LC.gen_text(gen) ~= LC.norm(LC.read_file(FILE.init)) then
    why[#why + 1] = "init.lua was edited since generation " .. gen
  end
  if LC.running_tag() ~= LOCK.neovim then
    why[#why + 1] = ("running Neovim %s, the LOCK says %s"):format(LC.running_tag(), LOCK.neovim)
  end
  refresh_lockfile()   -- compare what is declared and checked out, not a stale file
  local lf, moved = LC.json_read(FILE.lockfile) or {}, 0
  for name, p in pairs(lf) do
    if not LOCK.plugins[name] or LOCK.plugins[name].commit ~= p.commit then moved = moved + 1 end
  end
  for name in pairs(LOCK.plugins) do if not lf[name] then moved = moved + 1 end end
  if moved > 0 then why[#why + 1] = moved .. " plugin(s) differ from the LOCK" end
  local stale = undeclared_plugins()
  if stale > 0 then why[#why + 1] = stale .. " plugin directory(ies) no longer declared (:IDESync removes them)" end
  local tools = installed_tools()
  if tools then
    local changed, added = 0, 0
    for name, v in pairs(tools) do
      if not LOCK.tools[name] then added = added + 1 elseif LOCK.tools[name] ~= v then changed = changed + 1 end
    end
    if changed > 0 then why[#why + 1] = changed .. " tool version(s) differ from the LOCK" end
    if added > 0 then why[#why + 1] = added .. " tool(s) installed since the last pin" end
  end
  return #why == 0 and "pinned" or "modified", why
end

-- Rebuild every installed parser: they are compiled against one Neovim.
local function rebuild_parsers(cb)
  local ok, nts = pcall(require, "nvim-treesitter")
  if not ok then return cb(false, "nvim-treesitter is not available") end
  local list = nts.get_installed("parsers")
  if #list == 0 then return cb(true) end
  offer_sysdep("cc", function(cc_ok, why)
    if not cc_ok then return cb(false, why) end
    once("parsers:rebuild", function(done)
      busy("parsers", true)
      local saved_cache = vim.env.XDG_CACHE_HOME
      vim.env.XDG_CACHE_HOME = DIR.xdg
      nts.install(list, { force = true }):await(main(function(err)
        vim.env.XDG_CACHE_HOME = saved_cache
        busy("parsers", false)
        done(not err, err and tostring(err) or nil)
      end))
    end, cb)
  end)
end

local function clear_pending(key)
  local p = LC.json_read(FILE.pending) or {}
  p[key] = nil
  if next(p) then LC.json_write(FILE.pending, p) else os.remove(FILE.pending) end
end

-- A switch to another Neovim left the parsers to be rebuilt by the new one.
-- VimEnter fires once start-up is complete (plugins loaded, UI ready);
-- the work waits a further 800 ms (defer_fn) so the editor appears first.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local p = LC.json_read(FILE.pending)
    if HEADLESS or not (p and p.parsers) then return end
    vim.defer_fn(function()
      notify("Rebuilding Tree-sitter parsers for Neovim " .. LC.running_tag() .. " …")
      rebuild_parsers(function(ok, why)
        if ok then clear_pending("parsers"); notify("Parsers rebuilt.")
        else notify("Parser rebuild failed: " .. tostring(why) .. " — :IDESync retries.", vim.log.levels.WARN) end
      end)
    end, 800)
  end,
})

-- :IDESync — make plugins, tools, languages and parsers match the LOCK.
-- The installer and every switch run it under the new Neovim, headless.
vim.api.nvim_create_user_command("IDESync", function()
  local ok_lazy, manage = pcall(require, "lazy.manage")
  if ok_lazy then
    notify("Plugins: installing and checking out the LOCK's commits …")
    -- lazy rewrites its lockfile from the checkouts after every operation, so
    -- hand it the LOCK afresh before each step rather than trusting the file.
    local lock = require("lazy.manage.lock")
    -- lazy.manage (install / restore / clean) and lazy.manage.lock are
    -- lazy.nvim internals, the same code its :Lazy commands run. lock.lock is
    -- its in-memory copy of the lockfile; _loaded = true stops it re-reading.
    local function from_lock()
      LC.json_write(FILE.lockfile, LOCK.plugins)
      lock.lock, lock._loaded = vim.deepcopy(LOCK.plugins), true
    end
    from_lock()
    manage.install({ wait = true, show = false, lockfile = true })
    from_lock()
    manage.restore({ wait = true, show = false })
    manage.clean({ wait = true, show = false })
    pin_lazy_self()
    pcall(lock.update)   -- the lockfile now records exactly what is checked out
  end
  -- The command-line tools the editor relies on everywhere: fzf (every
  -- fuzzy-finder key), ripgrep and fd. Fetched here, so they are present the
  -- first time the editor opens, not a few seconds after.
  notify("Command-line tools: " .. table.concat(vim.tbl_keys(PORTABLE), ", "))
  for name in pairs(PORTABLE) do
    ensure_portable(name, function(ok, why)
      if not ok then notify("Tool " .. name .. ": " .. tostring(why), vim.log.levels.WARN) end
    end)
  end
  for name in pairs(LOCK.tools) do
    mason_install(name, function(ok, why)
      if not ok then notify("Tool " .. name .. ": " .. tostring(why), vim.log.levels.WARN) end
    end)
  end
  wait_until_idle()
  if #LOCK.langs > 0 then notify("Languages: " .. table.concat(LOCK.langs, ", ")) end
  for _, id in ipairs(LOCK.langs) do ensure_lang(id, { force = true }) end
  wait_until_idle()
  if (LC.json_read(FILE.pending) or {}).parsers then
    rebuild_parsers(function(ok, why)
      if ok then clear_pending("parsers") else notify("Parser rebuild: " .. tostring(why), vim.log.levels.WARN) end
    end)
    wait_until_idle()
  end
  notify("Sync finished.")
end, { desc = "Bring plugins, tools and parsers in line with the LOCK" })

-- Switch the live generation, then sync it in a window you can watch.
local function go_to_generation(name, action)
  local ok, err = pcall(LC.switch, name)
  if not ok then return notify(action .. " failed: " .. tostring(err), vim.log.levels.ERROR) end
  LC.history(action, name)
  -- A new process: the Neovim and init.lua just switched to, run headless.
  -- "+cmd" runs an Ex command after start-up; "+qa" quits when it is done.
  local sync = { LC.current_exe(), "--headless", "+IDESync", "+qa" }
  local function done(code)
    notify(("Now on generation %s%s. Restart Neovim to use it."):format(name,
      code == 0 and "" or " (sync reported problems; see :IDEDoctor after the restart)"))
  end
  if HEADLESS then return done(vim.system(sync):wait().code) end
  float_term(sync, action .. " → " .. name, done)
end

-- :IDEUpdate [--all | vX.Y.Z] — try something newer as a candidate generation.
--   (no argument)  check what is newer, then choose in a checklist
--   --all          take everything newer, without asking
--   vX.Y.Z         change only Neovim, to that release
-- Whatever is taken becomes a candidate: restart, try it (:IDEDiff shows
-- what changed), then :IDEPin keeps it or :IDERollback drops it.
local tag_cache
local function release_tags()
  tag_cache = tag_cache or LC.release_tags()
  return tag_cache
end

-- Plugins `name` depends on, directly or not, as declared in its spec
-- (lazy.nvim keeps `dependencies` as a list of plugin names).
local function plugin_deps(name, out)
  out = out or {}
  local ok, cfg = pcall(require, "lazy.core.config")
  local p = ok and cfg.plugins[name]
  for _, dep in ipairs(p and p.dependencies or {}) do
    if not out[dep] then out[dep] = true; plugin_deps(dep, out) end
  end
  return out
end

-- Find everything newer, without changing anything, and call back with a
-- list of items: { kind = "neovim" | "plugin" | "tool", name, detail, … }.
-- Plugins: lazy.nvim's check fetches each repository and records in
-- plugin._.updates where an update would move it (from/to commits).
-- Tools: the Mason registry is refreshed, then each installed package's
-- version is compared with the latest.
local function check_updates(cb)
  local items, problems = {}, {}
  local newest = release_tags()[#release_tags()]
  local cur, new = LC.parse_tag(LOCK.neovim), newest and LC.parse_tag(newest)
  if new and cur and (new[1] > cur[1] or (new[1] == cur[1] and (new[2] > cur[2] or (new[2] == cur[2] and new[3] > cur[3])))) then
    local minor = new[1] ~= cur[1] or new[2] ~= cur[2]
    items[#items + 1] = { kind = "neovim", name = "Neovim", tag = newest,
      detail = ("%s → %s%s"):format(LOCK.neovim, newest, minor and "   (new minor version: plugins not yet proven on it)" or "") }
  end
  local jobs = {}
  jobs[#jobs + 1] = function(done)
    local ok_lazy, manage = pcall(require, "lazy.manage")
    if not ok_lazy then return done(false, "lazy.nvim is not available") end
    manage.check({ show = false }):wait(main(function()
      local cfg = require("lazy.core.config")
      local names = vim.tbl_keys(cfg.plugins)
      table.sort(names)
      for _, name in ipairs(names) do
        local p = cfg.plugins[name]
        local up = p._.updates
        if up and up.from and up.to and up.from.commit ~= up.to.commit then
          local n = git_lines(p.dir, { "rev-list", "--count", up.from.commit .. ".." .. up.to.commit })
          n = n and tonumber(n[1])
          items[#items + 1] = { kind = "plugin", name = name,
            detail = n and ("%d new commit%s"):format(n, n == 1 and "" or "s") or "new commits" }
        end
      end
      done(true)
    end))
  end
  jobs[#jobs + 1] = function(done)
    local ok_reg, reg = pcall(require, "mason-registry")
    if not ok_reg then return done(true) end
    reg.update(main(function(success)
      mason_refreshed, mason_offline = true, not success
      if not success then return done(false, "the Mason registry could not be downloaded") end
      for _, pkg in ipairs(reg.get_installed_packages()) do
        local have = pkg:get_installed_version()
        local ok_v, latest = pcall(pkg.get_latest_version, pkg)
        if ok_v and have and latest ~= have then
          items[#items + 1] = { kind = "tool", name = pkg.name, pkg = pkg, detail = ("%s → %s"):format(have, latest) }
        end
      end
      done(true)
    end))
  end
  all(jobs, function(results)
    for _, r in ipairs(results) do if not r.ok and r.why then problems[#problems + 1] = r.why end end
    -- Neovim first, then plugins, then tools; each group sorted by name.
    local order = { neovim = 1, plugin = 2, tool = 3 }
    table.sort(items, function(a, b)
      if a.kind ~= b.kind then return order[a.kind] < order[b.kind] end
      return a.name < b.name
    end)
    cb(items, problems)
  end)
end

-- Make the chosen items a candidate: the Neovim build (if chosen) goes in
-- place, then the chosen plugins and tools are updated. Parsers follow
-- nvim-treesitter, whose plugin decides their versions.
local function apply_updates(chosen, scope)
  local ok, err = pcall(function()
    local base = LC.gen_current() or LC.fail("no generation stored yet; :IDEPin first")
    local tag, plugins, tools, parsers = LOCK.neovim, {}, {}, false
    for _, it in ipairs(chosen) do
      if it.kind == "neovim" then tag = it.tag
      elseif it.kind == "plugin" then
        plugins[#plugins + 1] = it.name
        if it.name == "nvim-treesitter" then parsers = true end
      else tools[#tools + 1] = it.pkg end
    end
    if tag ~= LC.current_tag() then
      LC.fetch_neovim(tag)
      LC.set_current(tag)
      local p = LC.json_read(FILE.pending) or {}
      p.parsers = true   -- parsers are compiled against one Neovim
      LC.json_write(FILE.pending, p)
    end
    LC.json_write(FILE.candidate, { base = base, prev = LOCK.neovim, new = tag, scope = scope, count = #chosen })
    local names = vim.tbl_map(function(it) return it.kind == "neovim" and ("nvim " .. it.tag) or it.name end, chosen)
    LC.history("update", ("%s (candidate)"):format(table.concat(names, ", ")))

    local jobs = {}
    if #plugins > 0 then
      jobs[#jobs + 1] = function(cb)
        -- show = false: no :Lazy window; only the named plugins are updated.
        require("lazy.manage").update({ show = false, plugins = plugins }):wait(function() cb(true) end)
      end
    end
    for _, pkg in ipairs(tools) do
      jobs[#jobs + 1] = function(cb)
        pkg:install({}, main(function(s, e) cb(s, not s and (pkg.name .. ": " .. tostring(e)) or nil) end))
      end
    end
    local ok_ts, nts = pcall(require, "nvim-treesitter")
    if parsers and ok_ts and #nts.get_installed("parsers") > 0 then
      jobs[#jobs + 1] = function(cb)
        local saved_cache = vim.env.XDG_CACHE_HOME
        vim.env.XDG_CACHE_HOME = DIR.xdg
        -- nvim-treesitter's update returns a task; :await(cb) calls back when
        -- it ends (err is nil on success).
        nts.update():await(main(function(e)
          vim.env.XDG_CACHE_HOME = saved_cache
          cb(not e, e and ("parsers: " .. tostring(e)) or nil)
        end))
      end
    end
    notify(("Updating %d item(s) …"):format(#chosen))
    busy("update", true)
    all(jobs, function(results)
      busy("update", false)
      local problems = {}
      for _, r in ipairs(results) do if not r.ok and r.why then problems[#problems + 1] = r.why end end
      -- One line (a longer message brings up "Press ENTER").
      notify(#problems == 0 and "Candidate ready. Restart to try it; :IDEDiff, then :IDEPin or :IDERollback."
        or ("Candidate ready with problems: %s"):format(table.concat(problems, "; ")),
        #problems == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
    end)
  end)
  if not ok then notify("Update failed: " .. tostring(err), vim.log.levels.ERROR) end
end

-- The checklist: one line per item, nothing ticked at first. Ticking a plugin
-- also ticks the plugins it depends on that have updates too (not the other
-- way round); a dependency of a ticked plugin says so, even if unticked.
local function choose_updates(items)
  local on = {}
  local index = {}   -- plugin name -> item number
  for i, it in ipairs(items) do if it.kind == "plugin" then index[it.name] = i end end
  local head = { "Space ticks · a all · n none · Enter updates the ticked items · q cancels", "" }
  local namew = 0
  for _, it in ipairs(items) do namew = math.max(namew, #it.name) end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local function render()
    local needed_by = {}   -- dependency -> the ticked plugin needing it
    for i, it in ipairs(items) do
      if on[i] and it.kind == "plugin" then
        for dep in pairs(plugin_deps(it.name)) do needed_by[dep] = needed_by[dep] or it.name end
      end
    end
    local lines = vim.list_extend({}, head)
    for i, it in ipairs(items) do
      local note = it.kind == "plugin" and needed_by[it.name] and ("   (needed by " .. needed_by[it.name] .. ")") or ""
      lines[#lines + 1] = ("%s %-" .. namew .. "s   %s%s"):format(on[i] and "[x]" or "[ ]", it.name, it.detail, note)
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  local function current() return vim.api.nvim_win_get_cursor(0)[1] - #head end
  local function toggle()
    local i = current()
    if not items[i] then return end
    on[i] = not on[i]
    if on[i] and items[i].kind == "plugin" then
      for dep in pairs(plugin_deps(items[i].name)) do
        if index[dep] then on[index[dep]] = true end
      end
    end
    render()
  end
  local function set_all(v) for i in ipairs(items) do on[i] = v end; render() end

  render()
  local w = math.min(vim.o.columns - 4, math.max(78, namew + 60))
  local h = math.min(vim.o.lines - 4, #items + #head)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = h, border = "rounded",
    row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
    title = " IDE update ", title_pos = "center",
  })
  -- No inherited line numbers; one line per item (no wrapping), the current
  -- one highlighted.
  vim.wo[win].number, vim.wo[win].relativenumber = false, false
  vim.wo[win].wrap, vim.wo[win].cursorline = false, true
  vim.api.nvim_win_set_cursor(win, { #head + 1, 0 })
  local o = { buffer = buf, nowait = true }
  map("n", "<Space>", toggle, o)
  map("n", "a", function() set_all(true) end, o)
  map("n", "n", function() set_all(false) end, o)
  map("n", "q", "<cmd>close<CR>", o)
  map("n", "<Esc>", "<cmd>close<CR>", o)
  map("n", "<CR>", function()
    local chosen = {}
    for i, it in ipairs(items) do if on[i] then chosen[#chosen + 1] = it end end
    if #chosen == 0 then return notify("Nothing ticked: Space ticks an item, a ticks all.", vim.log.levels.WARN) end
    vim.api.nvim_win_close(win, true)
    apply_updates(chosen, "selected")
  end, o)
end

-- cmd.args is the whole argument text ("" when none was given).
vim.api.nvim_create_user_command("IDEUpdate", function(cmd)
  if LC.lexists(FILE.candidate) then
    return notify("A candidate is being tried: :IDEPin keeps it, :IDERollback drops it.", vim.log.levels.WARN)
  end
  local arg = cmd.args ~= "" and cmd.args or nil
  if arg and arg ~= "--all" then
    -- One Neovim release, nothing else.
    local ok, err = pcall(function()
      local tags = release_tags()
      if not vim.tbl_contains(tags, arg) then LC.fail(arg .. " is not a Neovim release of v0.12.0 or later") end
      local cur, new = LC.parse_tag(LOCK.neovim), LC.parse_tag(arg)
      if cur and (cur[1] ~= new[1] or cur[2] ~= new[2]) and not LC.ask(
        ("The LOCK's plugins were proven on Neovim %s. Switch to %s anyway?\n(:IDESwitch goes back to a proven generation.)")
          :format(LOCK.neovim, arg), false) then
        return
      end
      apply_updates({ { kind = "neovim", name = "Neovim", tag = arg } }, "neovim")
    end)
    if not ok then notify("Update failed: " .. tostring(err), vim.log.levels.ERROR) end
    return
  end
  if not LC.gen_current() then return notify("No generation stored yet; :IDEPin first.", vim.log.levels.ERROR) end
  notify("Checking for updates …")
  busy("update", true)
  local ok, err = pcall(check_updates, function(items, problems)
    busy("update", false)
    if #problems > 0 then notify("Some checks failed: " .. table.concat(problems, "; "), vim.log.levels.WARN) end
    if #items == 0 then return notify("Everything is up to date.") end
    if arg == "--all" then return apply_updates(items, "all") end
    if HEADLESS then
      -- No window to choose in: list what is newer, and how to take it.
      for _, it in ipairs(items) do print(("  %-28s %s"):format(it.name, it.detail)) end
      return print(":IDEUpdate --all takes all of these.")
    end
    choose_updates(items)
  end)
  if not ok then busy("update", false); notify("Update failed: " .. tostring(err), vim.log.levels.ERROR) end
end, {
  nargs = "?", desc = "Try newer Neovim, plugins and tools as a candidate: choose, --all, or one Neovim version",
  -- <Tab> offers --all, then the release tags, newest first. deepcopy:
  -- reverse() changes the list in place, and the cached one must stay in order.
  complete = function() return vim.list_extend({ "--all" }, vim.fn.reverse(vim.deepcopy(release_tags()))) end,
})

-- :IDEPin — the live state is proven: write it into init.lua and store it.
vim.api.nvim_create_user_command("IDEPin", function()
  local cand = LC.json_read(FILE.candidate)
  if cand and cand.new and LC.running_tag() ~= cand.new then
    return notify(("Restart Neovim first: the candidate (%s) is not the one running."):format(cand.new), vim.log.levels.WARN)
  end
  local state = generation_state()
  if state == "pinned" then return notify("Nothing new to pin: the live state is generation " .. LC.gen_current() .. ".") end
  local ok, err = pcall(function()
    local lk = live_lock()
    local text = LC.lock_replace(LC.read_file(FILE.init), lk)
    LC.write_atomic(FILE.init, text)
    local name = LC.gen_add(text)
    os.remove(FILE.candidate)
    LC.prune_builds({ [lk.neovim] = true })
    LC.history("pin", name)
    LOCK = lk   -- this session now agrees with the file
    notify(("Pinned generation %s: Neovim %s, %d plugins, %d tools, %d languages."):format(
      name, lk.neovim, vim.tbl_count(lk.plugins), vim.tbl_count(lk.tools), #lk.langs))
  end)
  if not ok then notify("Pin failed: " .. tostring(err), vim.log.levels.ERROR) end
end, { desc = "Record the live state as a new generation" })

-- :IDERollback — drop the candidate (or unpinned changes): back to the
-- generation in effect.
vim.api.nvim_create_user_command("IDERollback", function()
  local cand = LC.json_read(FILE.candidate)
  local target = cand and cand.base or LC.gen_current()
  if not target then return notify("No generation stored yet.", vim.log.levels.WARN) end
  if not cand and generation_state() == "pinned" then
    return notify("Nothing to roll back: the live state is generation " .. target .. ".")
  end
  go_to_generation(target, "rollback")
end, { desc = "Return to the generation in effect" })

-- :IDESwitch <generation> — move to any stored (proven) generation.
vim.api.nvim_create_user_command("IDESwitch", function(cmd)
  local name = cmd.args
  if not vim.tbl_contains(LC.gen_list(), name) then
    return notify("No such generation: " .. name .. " (Tab lists them)", vim.log.levels.WARN)
  end
  go_to_generation(name, "switch")
end, {
  nargs = 1, desc = "Switch to a stored generation",   -- exactly one argument
  complete = function() return vim.fn.reverse(LC.gen_list()) end,
})

-- :IDEExport [dir] [--history] — hand the generation in effect to another
-- machine. Only pinned states leave: candidates and unpinned edits never do.
vim.api.nvim_create_user_command("IDEExport", function(cmd)
  local with_history, dir = false, nil
  for _, a in ipairs(cmd.fargs) do
    if a == "--history" then with_history = true else dir = a end
  end
  dir = vim.fs.normalize(vim.fn.fnamemodify(dir or vim.fn.getcwd(), ":p"))
  local gen = LC.gen_current()
  if not gen then return notify("Nothing pinned yet: run :IDEPin first.", vim.log.levels.WARN) end
  local state, why = generation_state()
  if state ~= "pinned" then
    notify(("The live state is %s (%s). Exporting the pinned generation %s; :IDEPin first to include the changes.")
      :format(state, table.concat(why, "; "), gen), vim.log.levels.WARN)
  end
  local dest = joinpath(dir, "init.lua")
  local existing = LC.read_file(dest)
  if existing and LC.norm(existing) ~= LC.gen_text(gen) and not LC.ask(dest .. " exists. Overwrite it?", false) then return end
  LC.write_file(dest, LC.gen_text(gen))
  if with_history then
    for _, name in ipairs(LC.gen_list()) do LC.write_file(joinpath(dir, "generations", name), LC.gen_text(name)) end
  end
  -- The bootstrap scripts kept at install time go along, so the other
  -- machine needs no Neovim beforehand.
  local scripts = {}
  for _, name in ipairs(LC.SCRIPTS) do
    local text = LC.read_file(joinpath(DIR.boot, name))
    if text then LC.write_file(joinpath(dir, name), text); scripts[#scripts + 1] = name end
  end
  LC.history("export", gen .. " → " .. dir)
  local how = #scripts > 0 and ("sh %s (Windows: install.ps1)"):format(joinpath(dir, "install.sh"))
    or ("nvim -l %s install"):format(dest)
  notify(("Exported generation %s to %s%s. On the other machine: %s"):format(
    gen, dest, with_history and " (with history)" or "", how))
end, { nargs = "*", complete = "dir", desc = "Export the generation in effect" })

-- ---------------------------------------------------------------------------
-- 14b. :IDEAdd owner/repo — declare a new plugin without hand-editing
-- ---------------------------------------------------------------------------
-- Step by step:
--   1. checks the name, and that the plugin is not declared already;
--   2. asks git whether the repository exists (in the background, so the
--      editor stays usable while the network answers);
--   3. writes a spec between the @@PLUGINS markers in init.lua (section 12);
--   4. installs it with a separate headless Neovim, because lazy.nvim reads
--      its specs once at start-up and cannot add one to a running session;
--   5. opens init.lua at the new spec, so you can configure it there.
-- The plugin is NOT locked yet: try it after a restart, then :IDEPin records
-- its commit in the LOCK (or :IDERollback removes it again). Removing a plugin
-- needs no command: delete its spec, restart, and :IDEPin.
local PLUGINS_END = "-- @@PLUGINS END"

-- "owner/repo" or a git URL  →  spec source, lazy's plugin name, URL for git.
local function plugin_source(arg)
  local gh = arg:match("^https?://github%.com/([%w._-]+/[%w._-]+)")   -- a GitHub page URL
  local short = gh or arg:match("^([%w._-]+/[%w._-]+)$")
  if short then
    short = short:gsub("%.git$", "")
    -- lazy.nvim names a plugin after the last part of its source.
    return ('"%s"'):format(short), short:match("[^/]+$"), SETTINGS.github .. "/" .. short .. ".git"
  end
  if arg:match("^%a[%w+.-]*://") or arg:match("^git@") then   -- any other git URL
    local name = arg:gsub("/+$", ""):match("[^/:]+$"):gsub("%.git$", "")
    return ('url = "%s"'):format(arg), name, arg
  end
end

-- Run a command; call back on the main loop. vim.system(cmd, opts, on_exit)
-- returns at once and calls on_exit later from libuv's "fast" context, where
-- most of the API is off limits, so vim.schedule_wrap moves the callback onto
-- the main loop. Headless runs (scripts, tests) have no loop turning after the
-- command line is done, so there we simply wait.
local function run_then(cmd, opts, cb)
  if HEADLESS then return cb(vim.system(cmd, opts):wait()) end
  vim.system(cmd, opts, vim.schedule_wrap(cb))
end

local function add_plugin(arg)
  local source, name, url = plugin_source(arg)
  if not source then
    return notify("Usage: :IDEAdd owner/repo   (or a git URL)", vim.log.levels.WARN)
  end
  local ok_cfg, cfg = pcall(require, "lazy.core.config")
  if ok_cfg and (cfg.plugins[name] or cfg.spec.disabled[name]) then
    return notify(name .. " is already declared in init.lua.", vim.log.levels.WARN)
  end
  -- Never overwrite edits you have not saved: bufnr(path) is -1 when the file
  -- is not open; vim.bo[buf].modified is the buffer's 'modified' flag.
  local buf = vim.fn.bufnr(FILE.init)
  if buf ~= -1 and vim.bo[buf].modified then
    return notify("init.lua has unsaved changes in a buffer: write or discard them first.", vim.log.levels.WARN)
  end
  local text = LC.read_file(FILE.init) or ""
  local at = text:find("\n%s*" .. vim.pesc(PLUGINS_END))   -- vim.pesc escapes Lua pattern characters
  if not at then
    return notify("init.lua has no " .. PLUGINS_END .. " marker (section 12); add the spec by hand.", vim.log.levels.ERROR)
  end

  notify("Checking " .. url .. " …")
  -- ls-remote asks the server for its refs without cloning. GIT_TERMINAL_PROMPT=0:
  -- a private or mistyped repository fails at once instead of asking for a password.
  run_then({ "git", "ls-remote", "--exit-code", url, "HEAD" },
    { text = true, timeout = 30000, env = { GIT_TERMINAL_PROMPT = "0" } }, function(r)
    if r.code ~= 0 then
      return notify(("%s is not a reachable git repository: %s"):format(url, vim.trim(r.stderr or "")), vim.log.levels.ERROR)
    end
    local spec = {
      "",
      ("  -- %s — added by :IDEAdd on %s. Try it, then :IDEPin locks its commit."):format(arg, os.date("%Y-%m-%d")),
      "  {",
      ("    %s,"):format(source),
      "    -- Most Lua plugins need their setup() called: uncomment opts (lazy.nvim",
      "    -- then calls require(\"<main module>\").setup(opts)). Options: its README,",
      ("    -- or :help %s once installed."):format((name:gsub("%.n?vim$", ""):gsub("^n?vim%-", ""))),
      "    -- opts = {},",
      "  },",
    }
    -- Insert before the line holding the end marker (at points at its newline).
    local new = text:sub(1, at) .. table.concat(spec, "\n"):sub(2) .. "\n" .. text:sub(at + 1)
    LC.write_atomic(FILE.init, new)
    -- Line of the new spec's "{", for the cursor: count the newlines before it.
    local line = select(2, text:sub(1, at):gsub("\n", "")) + 2
    LC.history("add", name)

    -- A fresh headless Neovim reads the new spec; "Lazy! install" (! = wait
    -- until done) clones what is missing. v:progpath is this Neovim's binary.
    local cmd = { vim.v.progpath, "--headless", "+Lazy! install", "+qa" }
    local function done(code)
      if code ~= 0 then
        return notify("Installing " .. name .. " failed; restart Neovim and lazy.nvim retries.", vim.log.levels.WARN)
      end
      if not HEADLESS then
        -- bang = true: reload from disk (the buffer, if open, has no unsaved
        -- changes: checked above), then put the cursor on the new spec.
        vim.cmd.edit({ args = { vim.fn.fnameescape(FILE.init) }, bang = true })
        pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
      end
      notify(("%s installed. Restart Neovim to load it; :IDEPin locks it, :IDERollback removes it."):format(name))
    end
    if HEADLESS then return done(vim.system(cmd):wait().code) end
    float_term(cmd, "IDEAdd → " .. name, done)
  end)
end

-- nvim_create_user_command(name, fn, opts) defines an Ex command (:IDEAdd).
-- fn receives a table describing the call: .args is the argument text,
-- .fargs the same split on spaces. opts.nargs = 1: exactly one argument.
vim.api.nvim_create_user_command("IDEAdd", function(cmd) add_plugin(cmd.args) end, {
  nargs = 1, desc = "Declare and install a new plugin (owner/repo or a git URL)",
})

-- ---------------------------------------------------------------------------
-- 14c. :IDEDoctor — what is present, where it came from, and what is missing
-- ---------------------------------------------------------------------------
local function source_of(bin)
  local path = vim.fn.exepath(bin)
  if path == "" then return nil end
  path = vim.fs.normalize(path)
  if path:find(vim.fs.normalize(joinpath(DIR.data, "mason")), 1, true) then return "mason" end
  if path:find(vim.fs.normalize(DIR.home), 1, true) then return "sandbox" end
  return "system"
end

-- Show a report (a list of lines) in a centred floating window; q closes it.
-- Without a UI (--headless) the lines are printed instead.
local function show_report(title, L)
  if HEADLESS then print(table.concat(L, "\n")); return end
  -- A scratch buffer (not listed, never saved); bufhidden = "wipe" deletes it
  -- as soon as its window closes.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, L)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local w = math.min(vim.o.columns - 4, 120)
  local h = math.min(vim.o.lines - 4, #L)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = h, border = "rounded",
    row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
    title = " " .. title .. " ", title_pos = "center",
  })
  -- A floating window inherits the editor's line numbers; a report has none.
  vim.wo[win].number, vim.wo[win].relativenumber = false, false
  -- q closes the window; buffer = buf keeps this mapping inside it, nowait
  -- answers at once even if longer mappings start with q.
  map("n", "q", "<cmd>close<CR>", { buffer = buf, nowait = true })
end

vim.api.nvim_create_user_command("IDEDoctor", function()
  local L = {}
  local function add(s) L[#L + 1] = s end
  local function mark(ok) return ok and "✓" or "✗" end
  add(("Super IDE doctor — Neovim %s · %s/%s · %s"):format(LC.running_tag(), OS, ARCH, vim.v.progpath))
  add("")
  local state, why = generation_state()
  add("Generation")
  add(("  state      %s"):format(({ pinned = "pinned ✓", modified = "unpinned changes", candidate = "candidate" })[state]))
  for _, w in ipairs(why) do add("             · " .. w) end
  if state ~= "pinned" then add("             :IDEDiff lists the changes") end
  add(("  in effect  %s   (%d stored; :IDESwitch lists them)"):format(LC.gen_current() or "none", #LC.gen_list()))
  add(("  LOCK       Neovim %s · %d plugins · %d tools · pinned %s"):format(
    LOCK.neovim, vim.tbl_count(LOCK.plugins), vim.tbl_count(LOCK.tools), LOCK.pinned ~= "" and LOCK.pinned or "never"))
  local hist = read_records("history.tsv")
  if #hist > 0 then
    add("  history")
    for i = math.max(1, #hist - 4), #hist do add(("    %s  %-8s %s"):format(hist[i][1], hist[i][2], hist[i][3] or "")) end
  end
  add("")
  add("Where Super IDE lives, and what it set aside")
  for _, k in ipairs({ "config", "data", "state", "cache" }) do
    local orig = DIR[k] .. "-orig"
    local kept = (uv.fs_lstat(orig) ~= nil) and ("   previous: " .. orig) or ""
    add(("  %-6s %s%s"):format(k, DIR[k], kept))
  end
  add(("  neovim %s"):format(LC.lexists(DIR.opt) and joinpath(DIR.opt, "current") or "(not installed by Super IDE)"))
  if uv.fs_stat(DIR.config .. "-orig") then add("  Your previous configuration runs with:  NVIM_APPNAME=nvim-orig nvim") end
  add("  Stock Neovim without any configuration:  nvim --clean")
  if uv.fs_stat(DIR.trash) then add("  State kept from an earlier uninstall: " .. DIR.trash) end
  add("")
  add("Core tools")
  for _, key in ipairs({ "git", "curl", "cc", "unzip" }) do
    local d = SYSDEPS[key]
    local cmd = not d:ok() and sysdep_command(d)
    add(("  %s %-10s %s"):format(mark(d:ok()), key, cmd and ("→ " .. cmd) or ""))
  end
  for _, b in ipairs({ "rg", "fd", "fzf", "tree-sitter" }) do
    local s = source_of(b)
    add(("  %s %-10s %s"):format(mark(s), b, s or "(fetched automatically when needed)"))
  end
  add("")
  add("Runtimes")
  local node = cmd_major_version({ "node", "--version" }, "^v(%d+)")
  add(("  %s node       %s"):format(mark(node and node >= 18), node and ("v" .. node .. " · " .. source_of("node"))
    or "(portable LTS fetched on first web/JS file)"))
  local jhome = jdk_home_from(JDK_DIR)
  local jsys = java_major("java")
  add(("  %s jdk 21+    %s"):format(mark(jhome or (jsys or 0) >= 21),
    jhome and ("sandbox · " .. jhome) or (jsys and ("system java " .. jsys) or "(portable JDK fetched on first .java)")))
  local py = python_cmd()
  add(("  %s python     %s"):format(mark(py), py or "not found — needed by Python, Java and clang-format tooling"))
  for _, b in ipairs({ "go", "cargo", "php" }) do
    add(("  %s %-10s %s"):format(mark(exe(b)), b, exe(b) and source_of(b) or "not found (only needed for that language)"))
  end
  add("")
  add("Languages")
  local ids = vim.tbl_keys(LANGS)
  table.sort(ids)
  local have_ts = ts_installed()
  for _, id in ipairs(ids) do
    local lang = LANGS[id]
    local parts = {}
    local ts_ok = true
    for _, l in ipairs(lang.ts) do if not have_ts[l] then ts_ok = false end end
    parts[#parts + 1] = "parser " .. mark(ts_ok)
    for _, t in ipairs(lang.tools) do
      local s = source_of(t.bin)
      parts[#parts + 1] = ("%s %s%s"):format(t.bin, mark(s), s and ("(" .. s .. ")") or "")
    end
    if lang.dap then parts[#parts + 1] = "debug:" .. lang.dap end
    add(("  %-22s %s"):format(lang.label, table.concat(parts, "  ")))
    for _, problem in ipairs(P.failed[id] or {}) do add("      ! " .. problem) end
  end
  add("")
  local links = read_records("clangd-links.tsv")
  add(("clangd index links: %d (each <project>/.cache → %s)"):format(#links, DIR.clangd))
  local pkgs = read_records("system-packages.tsv")
  if #pkgs > 0 then
    add("System packages installed through Super IDE (kept on uninstall):")
    for _, p in ipairs(pkgs) do add("  " .. p[2] .. "   (" .. p[3] .. ")") end
  end
  add("")
  add("Missing pieces install themselves when a file of that language is opened;")
  add(":IDEInstall <lang> (or all) does it now.  q closes this window.")
  show_report("IDE doctor", L)
end, { desc = "Report what the IDE has, lacks, and where things came from" })

-- :IDEDiff — what the live state changes against the generation in effect
-- (its LOCK and its init.lua): the Neovim release, each plugin's commits with
-- their subjects, tool versions, languages newly in use, and the text of
-- init.lua. It answers "what did this :IDEUpdate bring?" before :IDEPin or
-- :IDERollback, and does the same for unpinned changes made by hand.
-- Commit subjects come from the plugins' local git history (an update has
-- already fetched them), so no network is needed.
local DIFF_SUBJECTS = 6   -- commit subjects shown per plugin

-- A plugin's directory: from lazy.nvim's spec, else its default place.
local function plugin_dir(name)
  local ok, cfg = pcall(require, "lazy.core.config")
  local p = ok and cfg.plugins[name]
  return p and p.dir or joinpath(DIR.data, "lazy", name)
end

-- How one plugin moved from commit `old` to `new`: a summary, then the
-- subjects of the newest commits (or of those undone, when it went back).
local function plugin_moves(name, old, new)
  local dir = plugin_dir(name)
  local function count(range)
    local out = git_lines(dir, { "rev-list", "--count", range })
    return out and tonumber(out[1])
  end
  local fwd, back = count(old .. ".." .. new), count(new .. ".." .. old)
  if not fwd or not back then return "history not available locally", {} end
  local range = fwd > 0 and (old .. ".." .. new) or (new .. ".." .. old)
  local subjects = git_lines(dir, { "log", "--format=%h %s", "-n", tostring(DIFF_SUBJECTS), range }) or {}
  local total = fwd > 0 and fwd or back
  if total > #subjects then subjects[#subjects + 1] = ("… %d more"):format(total - #subjects) end
  local what = fwd > 0 and ("%d new commit%s"):format(fwd, fwd == 1 and "" or "s")
    or ("%d commit%s back"):format(back, back == 1 and "" or "s")
  if fwd > 0 and back > 0 then what = what .. (", %d dropped (history rewritten)"):format(back) end
  return what, subjects
end

vim.api.nvim_create_user_command("IDEDiff", function()
  local state = generation_state()   -- also refreshes lazy.nvim's lockfile
  local gen = LC.gen_current()
  local L, changes = {}, 0
  local function add(s) L[#L + 1] = s end
  local short = function(c) return c and c:sub(1, 7) or "?" end
  add(("Changes against generation %s  (state: %s)"):format(gen or "none",
    ({ pinned = "pinned", modified = "unpinned changes", candidate = "candidate" })[state]))
  add("")

  -- Neovim: the build in place (a candidate's, once :IDEUpdate has run).
  local tag = LC.current_tag() or LC.running_tag()
  if tag ~= LOCK.neovim then
    changes = changes + 1
    add(("Neovim   %s → %s%s"):format(LOCK.neovim, tag, LC.running_tag() ~= tag and "   (restart to run it)" or ""))
    add("")
  end

  -- Plugins: the LOCK's commits against those checked out now.
  local lf = LC.json_read(FILE.lockfile) or {}
  local names, seen = {}, {}
  for _, t in ipairs({ LOCK.plugins, lf }) do
    for name in pairs(t) do if not seen[name] then seen[name] = true; names[#names + 1] = name end end
  end
  table.sort(names)
  local block, same = {}, 0
  for _, name in ipairs(names) do
    local old = LOCK.plugins[name] and LOCK.plugins[name].commit
    local new = lf[name] and lf[name].commit
    if old == new then
      same = same + 1
    elseif not old then
      block[#block + 1] = ("  %-24s new, at %s"):format(name, short(new))
    elseif not new then
      block[#block + 1] = ("  %-24s removed (was %s)"):format(name, short(old))
    else
      local what, subjects = plugin_moves(name, old, new)
      block[#block + 1] = ("  %-24s %s → %s   %s"):format(name, short(old), short(new), what)
      for _, s in ipairs(subjects) do block[#block + 1] = "      " .. s end
    end
  end
  local moved = #names - same
  changes = changes + moved
  add(("Plugins  %d changed, %d unchanged"):format(moved, same))
  vim.list_extend(L, block)
  add("")

  -- Tools: versions installed now against the LOCK. A pinned tool that is not
  -- installed here only means that language was not opened on this machine.
  local tools = installed_tools() or {}
  local tnames = vim.tbl_keys(tools)
  table.sort(tnames)
  local tblock, tsame = {}, 0
  for _, name in ipairs(tnames) do
    local old, new = LOCK.tools[name], tools[name]
    if old == new then
      tsame = tsame + 1
    elseif not old then
      tblock[#tblock + 1] = ("  %-24s new, %s"):format(name, new)
    else
      tblock[#tblock + 1] = ("  %-24s %s → %s"):format(name, old, new)
    end
  end
  changes = changes + #tblock
  add(("Tools    %d changed, %d unchanged"):format(#tblock, tsame))
  vim.list_extend(L, tblock)
  add("")

  -- Languages in use that the LOCK does not list yet.
  local newlangs = vim.tbl_filter(function(id) return not vim.tbl_contains(LOCK.langs, id) end, used_langs(tools))
  if #newlangs > 0 then
    changes = changes + #newlangs
    add("Languages  new: " .. table.concat(newlangs, ", "))
    add("")
  end

  -- init.lua itself: edits since the generation was stored (settings, specs
  -- added by :IDEAdd, …), as a unified diff with two lines of context.
  local stored = gen and LC.gen_text(gen)
  local text = LC.norm(LC.read_file(FILE.init) or "")
  if stored and stored ~= text then
    changes = changes + 1
    add("init.lua  edited since the generation was stored")
    for _, line in ipairs(vim.split(vim.text.diff(stored, text, { ctxlen = 2 }), "\n", { trimempty = true })) do
      add("  " .. line)
    end
    add("")
  end

  if changes == 0 then
    L = { ("No changes: the live state matches generation %s."):format(gen or "none") }
  else
    add(":IDEPin keeps these changes as a new generation; :IDERollback drops them.  q closes this window.")
  end
  show_report("IDE diff", L)
end, { desc = "Show what the live state changes against the generation in effect" })

-- :IDEUninstall — hand over to a Neovim running from a temporary copy. It
-- waits for this one to exit (nothing can remove the directories it is using),
-- restores your previous configuration from nvim-orig, undoes the changes made
-- inside projects, and keeps or deletes Super IDE's state.
vim.api.nvim_create_user_command("IDEUninstall", function()
  if not LC.lexists(FILE.marker) then
    return notify("Super IDE was not installed by its installer here; nothing to uninstall.", vim.log.levels.WARN)
  end
  local msg = {
    "Remove Neovim Super IDE?", "",
    "Your previous configuration (*-orig directories) comes back, the `nvim` command",
    "is handed back, and clangd's links and .git/info/exclude lines are undone.", "",
    "Super IDE's own state — plugins, tools, generations, edit history — can be kept in",
    "  " .. DIR.trash,
    "so that a later install restores it instead of downloading everything again.", "",
    "Neovim quits now; the removal finishes in the background a moment later. Its log:",
    "  " .. joinpath(vim.uv.os_tmpdir(), LC.UNINSTALL_PREFIX .. "*", "uninstall.log"),
  }
  -- confirm(msg, choices, default): a dialog; "&K" makes K the shortcut key.
  -- Returns the number of the choice (3, Cancel, is the default; 0 = Esc).
  local choice = vim.fn.confirm(table.concat(msg, "\n"), "&Keep state in trash\n&Delete everything\n&Cancel", 3)
  if choice ~= 1 and choice ~= 2 then return end
  -- Unsaved changes are settled before anything starts: the uninstaller waits
  -- for this Neovim to exit, so a quit that is cancelled half-way would leave
  -- it waiting, and it would uninstall whenever Neovim is closed later.
  -- getbufinfo({ bufmodified = 1 }) lists buffers with unsaved changes. Only
  -- file buffers count ('buftype' "" or "acwrite"): scratch buffers such as
  -- the start screen are "modified" too, but quitting never asks about them,
  -- and terminal buffers simply end their programs.
  local unsaved = {}
  for _, b in ipairs(vim.fn.getbufinfo({ bufmodified = 1 })) do
    local bt = vim.bo[b.bufnr].buftype
    if bt == "" or bt == "acwrite" then
      unsaved[#unsaved + 1] = b.name ~= "" and vim.fn.fnamemodify(b.name, ":~:.") or "[No Name]"
    end
  end
  if #unsaved > 0 then
    return notify("Write or discard these first, then run :IDEUninstall again: " .. table.concat(unsaved, ", "),
      vim.log.levels.WARN)
  end
  local ok, err = pcall(LC.uninstall_handoff, choice == 1, true)
  if not ok then return notify("Uninstall could not start: " .. tostring(err), vim.log.levels.ERROR) end
  vim.cmd("qall!")   -- nothing unsaved is left (checked above); ! also ends terminal jobs
end, { desc = "Remove Super IDE and restore the previous Neovim configuration" })
