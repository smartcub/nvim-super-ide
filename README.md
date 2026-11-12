<p align="center">
  <img src="assets/logo.svg" width="560" alt="Neovim Super IDE">
</p>

# Neovim Super IDE

A keyboard-first IDE in **one file**, `init.lua`, for Linux, macOS and Windows.
One command installs it with everything it needs. The file pins Neovim and
every plugin, so the same file builds the same IDE on any machine; each
approved state is kept as a *generation* you can return to or
move elsewhere. Your previous Neovim setup is set aside, not deleted, and
uninstalling restores it.

> [!IMPORTANT]
> **Network requirement.** Installing and using Super IDE downloads from
> GitHub and other international hosts: Neovim, every plugin, the language
> tools. Before installing, make sure the target machine can reach them
> reliably; otherwise the installation cannot complete. See
> [Network access](#network-access).

<a id="quick-links"></a>
<p align="center">
  <a href="#online-install">Online install</a> ·
  <a href="#local-install">Local install</a> ·
  <a href="#uninstall">Uninstall</a> ·
  <a href="#generations">Generations</a> ·
  <a href="#keymaps">Keymaps</a> ·
  <a href="#commands">Commands</a>
</p>

---

## Quick start

```sh
# 1. Install (Windows: see Online install)
curl -fsSL https://raw.githubusercontent.com/smartcub/nvim-super-ide/main/install.sh | sh

# 2. Open a new terminal, start the IDE and check it
nvim            # then  :IDEDoctor
```

- **Use it**: `nvim file.c`. Language servers, formatters and debuggers download
  the first time you open a file of that language. Leader is `,`.
- **Update**: `:IDEUpdate` moves to the newest release of Super IDE. Restart,
  try it, then `:IDEPin` to keep it or `:IDERollback` to drop it.
- **Remove**: `:IDEUninstall`.

---

## Install

### Online install

<p align="right"><a href="#quick-links">↑ Back to links</a></p>

No files needed.

```sh
# Ubuntu / Debian (also WSL), macOS
curl -fsSL https://raw.githubusercontent.com/smartcub/nvim-super-ide/main/install.sh | sh
```

```powershell
# Windows 10 / 11, in a PowerShell window
irm https://raw.githubusercontent.com/smartcub/nvim-super-ide/main/install.ps1 | iex
```

Then **open a new terminal** and run `nvim`; `:IDEDoctor` reports what is
installed and what is missing.

### Local install

<p align="right"><a href="#quick-links">↑ Back to links</a></p>

From a folder holding the repository files (an export, a download, a clone);
the scripts install the `init.lua` beside them.

| File | Purpose |
|:-----|:--------|
| `init.lua` | The IDE and its own installer, uninstaller and version manager |
| `install.sh` | Setup for Linux and macOS: system packages, pinned Neovim, then `init.lua install` |
| `install.ps1` | The same for Windows 10 / 11 |

| System | Command |
|:--|:--|
| Ubuntu / Debian (also WSL), macOS | `sh install.sh` |
| Windows 10 / 11 | `powershell -ExecutionPolicy Bypass -File install.ps1` |

`-ExecutionPolicy Bypass` applies to that run only. With Neovim **0.12+**
already present, `nvim -l init.lua install` also works; it does the same, except
that on macOS it only starts Apple's installer for missing packages.

### Options

- `--yes`: accept every default (required without a terminal, e.g. in CI).
- `--git-editor`: make git open commit messages in Super IDE
  (`git config --global core.editor nvim`; restored on uninstall).

With the one-liners, pass options after `sh -s --` (`… | sh -s -- --yes`); on
Windows use `& ([scriptblock]::Create((irm <URL>))) --yes`, because `irm | iex`
cannot pass arguments.

To install a particular release instead of the newest, set `SUPER_IDE_REF`:
`curl … | SUPER_IDE_REF=v1.2.0 sh`, or in PowerShell
`$env:SUPER_IDE_REF = 'v1.2.0'` before the `irm` line.

### Requirements

**Supported:** Ubuntu 22.04 / 24.04 and Debian (`apt-get`), macOS (Apple
silicon or Intel), Windows 10 1803+ and 11 (`winget`); x86_64 and arm64. Other
Linux distributions work, but you install the packages below yourself: the
script lists what is missing and stops only for required ones.

| Package | What it is for | Without it |
|:--|:--|:--|
| git | Plugins; listing Neovim releases | Cannot install |
| curl | Neovim, tools, runtimes | Cannot install |
| tar, unzip | Unpacking downloads (Windows ships tar, which also reads zip) | Cannot install / Mason cannot unpack zip releases |
| A C compiler | Building Tree-sitter parsers | Only basic regex highlighting |
| python3 with venv | Mason installs Python-based tools (basedpyright, debugpy, clang-format, the jdtls launcher) into private virtual environments | Python, Java and clang-format tooling cannot install. **Stock Ubuntu lacks `python3-venv`** |
| wl-clipboard or xclip | System clipboard in a graphical Linux session | No `"+` clipboard (OSC 52 still works over SSH) |

| System | What the script runs |
|:--|:--|
| Ubuntu / Debian | `sudo apt-get install -y` the missing ones of: `git curl tar unzip build-essential python3 python3-venv`, plus `wl-clipboard` or `xclip` in a graphical session |
| macOS | `xcode-select --install` (git, clang, python3); curl, tar and unzip are part of macOS. Homebrew is not needed |
| Windows | `winget install -e --id` `Git.Git`, `LLVM.LLVM` (clang) and `Python.Python.3.12`. Python must be on `PATH` (the installer's "Add Python to environment variables") |

Neovim itself is downloaded for you: the official release from
<https://github.com/neovim/neovim/releases>. On Linux it needs a recent glibc
(Ubuntu 22.04 or newer).

**Optional: the toolchains you write code with.** Not installed automatically,
since the version depends on your project:

| Language | Install it yourself (Ubuntu) |
|:--|:--|
| Go | `sudo apt install golang` or the tarball from go.dev |
| Rust | `curl https://sh.rustup.rs -sSf \| sh`, then `rustup component add rustfmt` |
| PHP | `sudo apt install php-cli` |
| Java (for your projects) | `sudo apt install openjdk-21-jdk` (jdtls gets its own JDK regardless) |
| Assembly (asm-lsp) | Built with Cargo, so Rust as above |

**Node.js and JDK 21 are not needed**: Super IDE downloads private portable
builds when a language server requires them.

> Install a Nerd Font (e.g. **MesloLGS NF**) on the machine that runs your
> terminal; over SSH that is your local machine.

### Network access

Installation and later use (language tools on first use, `:IDEUpdate`) download
from GitHub. In regions where access to GitHub is restricted, arrange reliable
access yourself before installing; otherwise the first download fails, typically
with `curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to github.com:443`.

Hosts used: `github.com` (Neovim, plugins, Mason packages, parsers),
`raw.githubusercontent.com` (Super IDE itself), `api.github.com` (Mason's registry), `nodejs.org`, `api.adoptium.net` (JDK),
`pypi.org` / `files.pythonhosted.org`, `registry.npmjs.org`, and your
distribution's package mirror. Mirrors are configured in [Settings](#settings).

### What installing changes

- **System packages** ([Requirements](#requirements)) are installed only after
  you approve the exact command; the system is never upgraded as a whole.
- **Neovim** goes to `~/.local/opt/super-ide` (Windows: `%LOCALAPPDATA%\super-ide`),
  apart from any system Neovim.
- **Your existing Neovim configuration** is renamed to `nvim-orig` and still
  runs ([Files and directories](#files-and-directories)).
- **The `nvim` command** starts Super IDE:
  - Linux / macOS: the link `~/.local/bin/nvim`. On Ubuntu, log in again if
    `~/.local/bin` is new; on macOS the installer offers to add a marked line
    to `~/.zprofile`.
  - Windows: an entry in the user `PATH`. A system-wide Neovim (winget's
    default) is found first; remove it (`winget uninstall Neovim.Neovim`) or
    start Super IDE by its full path.
- **State kept by an earlier uninstall** is offered for restoring.

**Installing over an existing Super IDE** shows a warning and asks first: the
file being installed replaces the live `init.lua` as it is, and changes you
made to your own `init.lua` are not merged. The generations stored so far are
kept. To move to a new release and keep your changes, use `:IDEUpdate`
([Generations](#generations)).

### Cancelling

Press **Ctrl+C** at any time to cancel the installation; every change it made
is reverted. An error is handled the same way. The message
`Nvim: Caught deadly signal 'SIGINT'` that Neovim prints first is expected.
System packages installed during the run are kept. Cancelling an import
restores the previous generation, which may take a few minutes.

---

## Uninstall

<p align="right"><a href="#quick-links">↑ Back to links</a></p>

```vim
:IDEUninstall          " asks keep-or-delete; finishes after Neovim exits
```
```bash
nvim -l ~/.config/nvim/init.lua uninstall      # from a terminal
```

`--keep-state` / `--discard-state` answer the question in advance; `--yes`
keeps the state.

- **Restored**: your previous configuration (`nvim-orig` back to `nvim`), git's
  `core.editor`, your `PATH` / `~/.zprofile`, and the clangd links inside your
  projects.
- **Removed**: the `nvim` command, the Neovim builds, the cache.
- **Kept or deleted, as you answer**: Super IDE's state (plugins, tools,
  generations, history). Kept, it moves to `~/.local/share/.super-ide-trash`
  (Windows: `%LOCALAPPDATA%\.super-ide-trash`) and the next install offers to
  restore it; delete that folder to remove it for good.
- **Left alone**: system packages (they are listed).

From `:IDEUninstall`, and on Windows, the removal finishes in the background
after Neovim exits (write or discard unsaved files first); its log is
`$TMPDIR/super-ide-uninstall-*/uninstall.log` (default `/tmp`; Windows:
`%TEMP%\super-ide-uninstall-*\uninstall.log`).

---

## Generations

<p align="right"><a href="#quick-links">↑ Back to links</a></p>

A **generation** is a complete `init.lua`: code plus a `LOCK` naming the Neovim
version and the plugin commits. Language tools (servers, formatters, debuggers)
are not part of it: each is installed at its latest version the first time you
open a file of its language, and stays installed whatever generation you switch
to. `:IDEDoctor` lists their versions. Every approved state is
stored as one, in `~/.local/share/nvim/super-ide/generations/`, named by date
and Neovim version. The workflow:

```
:IDEUpdate  →  restart, try it, :IDEDiff  →  :IDEPin       keep it as a new generation
                                          →  :IDERollback  drop it, back to the generation in effect
:IDESwitch <generation>                           go to any stored generation
:IDEExport [dir] [--history]                      take the generation in effect to another machine
```

| State | Meaning | Reached by |
|:--|:--|:--|
| **pinned** | Everything matches the generation in effect | Install, `:IDEPin`, `:IDERollback`, `:IDESwitch` |
| **unpinned changes** | You edited `init.lua` or ran `:Lazy update` | Using the IDE |
| **candidate** | Something newer is being tried | `:IDEUpdate`, `:IDEUpdateUnsafe` |

| Command | What it does |
|:--|:--|
| `:IDEUpdate` | Move to the newest **release of Super IDE** as a candidate: one `init.lua` whose Neovim and plugins were proven together. Your own changes to `init.lua` are merged in |
| `:IDEUpdate v1.2.0` | The same, to that release (Tab completes the releases) |
| `:IDEUpdateUnsafe` | Try what is newer **upstream**, unproven: choose in a checklist among Neovim and each plugin. `--all` takes everything; `v0.12.5` changes only Neovim (crossing a minor version asks first) |
| `:IDEDiff` | Show what the live state changes against the generation in effect: release, Neovim, each plugin's commits (with their subjects), edits to `init.lua` |
| `:IDEPin` | Approve the live state: write it into the `LOCK` of `init.lua` and store the file as a new generation |
| `:IDERollback` | Drop the candidate or the unpinned changes; return to the generation in effect. An edited `init.lua` is first set aside in `super-ide/rejected/` |
| `:IDESwitch <generation>` | Go to any stored generation (Tab lists them, newest first): its Neovim, its `init.lua`, its plugins |
| `:IDEExport [dir] [--history]` | Write the generation in effect to `dir/init.lua` (with `--history`, every stored generation too) |

**`:IDEUpdate` and your own changes.** Settings you changed and plugins you
added are carried into the new release automatically. Only when the release
changes the same lines as you did, you are asked first: going on installs the
release as published, and your version stays stored as a generation
(`:IDESwitch` returns to it). `:IDEUpdate` starts from a pinned state, so
`:IDEPin` or `:IDERollback` any unpinned changes first.

**The `:IDEUpdateUnsafe` checklist.** `Space` ticks the item under the cursor,
`a` ticks all, `n` none, `Enter` updates the ticked items, `q` cancels. Nothing
is ticked at first; ticking a plugin also ticks the plugins it depends on.

`:IDEDoctor` shows the release, the state and why, the generation in effect,
recent history, and the version of each installed language tool.

- **Only pinned generations are exported.** `:IDEExport` skips a candidate or
  unpinned edits and says so; `:IDEPin` first to include them.
- **Code and versions switch together.** A switch replaces `init.lua` and
  checks out that generation's Neovim and plugins, then rebuilds the
  parsers if Neovim changed, so any two stored generations can be switched safely.

### Moving to another machine

```
lab:   :IDEExport /media/usb
home:  sh /media/usb/install.sh          (Windows: install.ps1)
```

The export writes `init.lua` and the two scripts, so the target needs no Neovim.
(If Super IDE was installed without the scripts, only `init.lua` is written;
copy the scripts next to it, or run `nvim -l init.lua install` with Neovim 0.12+.)

On a machine without Super IDE this is a fresh install; otherwise the file is
imported as a new generation (with a `generations/` folder from `--history`, if
present). Either way the target gets the same Neovim and plugins; language
tools install there the first time each language is opened.

---

## Keymaps

<p align="right"><a href="#quick-links">↑ Back to links</a></p>

**Leader:** `,`

### Global (Normal mode)

| Key | Action |
|:--|:--|
| `-` | Oil (edit the parent directory as a buffer) |
| `<C-]>` | Go to definition (LSP, else tags) |
| `<C-h>` `<C-j>` `<C-k>` `<C-l>` | Window left / down / up / right |
| `<C-Left>`, `<C-Right>` | Window left / right (for terminals that eat `<C-h>`/`<C-l>`) |
| `<C-p>` | Find files |
| `<C-\>` | Toggle floating terminal |
| `<F2>` / `<F3>` | Previous / next buffer |
| `<F5>` | Debug: start or continue (fetches the adapter on first use) |
| `<F6>` | Run current file |
| `<F7>` | Run project (Cargo, Go module, CMake, Make, npm, Maven or Gradle; else the file) |
| `<F9>` | Toggle breakpoint |
| `<F10>` / `<F11>` / `<F12>` | Step over / into / out |
| `]h` / `[h` | Next / previous git change (in files tracked by git) |
| `,,<Space>` | Clear search highlight |
| `,,ev` | Edit `init.lua` |
| `,cg` | Toggle column guides (80/100/120) |
| `,db` | Conditional breakpoint |
| `,dr` | Debug REPL |
| `,du` | Debug UI toggle |
| `,e` | File explorer (neo-tree; closes itself when a file is opened) |
| `,f` | Format buffer |
| `,fb` | Buffers |
| `,fc` | Toggle cursor cross (cursorline + cursorcolumn) |
| `,ff` | Find files |
| `,fh` | Help tags |
| `,fo` | Recent files |
| `,hp` | Preview this git change (old and new lines) |
| `,hr` | Undo this git change (`u` brings it back) |
| `,hb` | Who changed this line, in which commit |
| `,hB` | Mark changes since the last push instead of the last commit (again: back) |
| `,ig` | Toggle indent guides |
| `,nf` | Generate a file header comment (neogen) |
| `,ng` | Generate a doc comment for the symbol under the cursor (neogen) |
| `,o` | Outline (symbols) |
| `,ql` | Restore last session |
| `,qs` | Restore session for this directory |
| `,rg` | Live grep |
| `,tf` | Toggle format-on-save |
| `,u` | Undo tree (built into Neovim 0.12) |

### When a language server is attached

| Key | Action |
|:--|:--|
| `<C-]>` | Go to definition |
| `gr` | References |
| `gy` | Type definition (falls back to definition) |
| `gI` | Implementation (falls back to definition) |
| `K` | Hover documentation |
| `[g` / `]g` | Previous / next diagnostic (also `[d` / `]d`) |
| `gl` | Diagnostics of the current line |
| `,rn` | Rename symbol |
| `,ca` | Code action (Normal and Visual mode) |
| `,ch` | Switch between source and header (clangd) |

`gr`, `gy` and `gI` open a picker when there are several results and jump
straight there when there is one.

### Insert, terminal and completion

| Mode | Key | Action |
|:--|:--|:--|
| Insert | `<Left>` at column 1 | Move to the end of the previous line |
| Insert | `<Right>` at end of line | Move to the start of the next line |
| Insert | `<CR>` | Accept the selected completion item; with none selected, a plain newline |
| Insert | `<Tab>` / `<S-Tab>` | Next / previous item, or jump within a snippet |
| Insert | `<Up>` / `<Down>` | Previous / next item while the menu is open |
| Insert | `<C-Space>` | Open completion / toggle documentation |
| Insert | `<C-k>` | Toggle signature help |
| Insert | `filehdr` | Snippet: file header for C, C++ and assembly |
| Terminal | `<Esc>` | Back to Normal mode (inside the fuzzy finder, `<Esc>` closes it) |

The sign column marks lines changed since the last commit: green `┃` added,
blue `┃` changed, `_` lines deleted below. It follows your typing, before any
save. After `,hB` it marks everything not yet pushed, committed or not.

### More keys

Defaults of Neovim and the plugins, unchanged by Super IDE but worth knowing.
Oil, the file tree, `:Git` and which-key list all of theirs with `g?` or `?`.

| Where | Key | Action |
|:--|:--|:--|
| Diff mode (`nvim -d a b`) | `]c` / `[c` | Next / previous difference |
| | `do` / `dp` | Take this difference from / put it into the other window |
| | `:diffupdate` | Compare again after edits |
| Folds | `za` / `zR` / `zM` | Toggle this fold / open all / close all |
| Comments | `gcc` / `gc{motion}` | Comment or uncomment a line / a range (Visual: `gc`) |
| Surround | `ysiw"` | Surround the word with `"` |
| | `cs"'` / `ds"` | Change `"` to `'` / delete the surrounding `"` |
| | Visual `S"` | Surround the selection with `"` |
| Lists | `[q` / `]q` | Previous / next quickfix item (e.g. grep results) |
| | `[b` / `]b` | Previous / next buffer |
| Links | `gx` | Open the link under the cursor in the browser |
| Finder (`,ff`, `,rg`, …) | `<C-v>` / `<C-s>` / `<C-t>` | Open in a vertical split / horizontal split / tab |
| `:Git` status window | `s` / `u` | Stage / unstage the file under the cursor |
| | `=` / `dv` | Show the changes inline / side by side |
| | `cc` | Commit |
| Oil (`-`) | `Enter` / `-` | Open / go to the parent directory |
| | Rename or delete lines, then `:w` | Rename or delete the files |
| File tree (`,e`) | `a` / `d` / `r` | New / delete / rename |
| Anywhere | `,` then wait | which-key lists every `,` key |

### Start screen

`nvim` without a file shows the logo above and a one-key menu:

```
  f  Find file        r  Recent files     g  Grep text
  s  Restore session  e  File explorer    c  Edit config
  d  IDE doctor       u  Plugins          q  Quit
```

### Clipboard

Locally, `unnamedplus` uses the system clipboard. **Over SSH**, copying uses
**OSC 52**, which places the text on your local clipboard; pasting uses an
internal cache. In tmux, set `set -g set-clipboard on`. Hold **Shift** while
dragging to use the terminal's own selection.

---

## Commands

<p align="right"><a href="#quick-links">↑ Back to links</a></p>

| Command | Purpose |
|:--|:--|
| `:IDEDoctor` | Generation state and history; what is installed, where it came from (system / Mason / sandbox), and what is missing — with the command to fix it |
| `:IDEInstall [lang… \| all]` | Provision languages now (no argument: the current buffer's language) |
| `:IDEPrewarm [dir]` | Scan a directory and provision every language found in it |
| `:IDEUpdate [vX.Y.Z]` | Move to the newest (or the named) release of Super IDE as a candidate, keeping your own changes ([Generations](#generations)) |
| `:IDEUpdateUnsafe [--all \| vX.Y.Z]` | Try upstream's newest Neovim and plugins, unproven, as a candidate: chosen in a checklist, all of them, or only another Neovim |
| `:IDEDiff` | What the live state changes against the generation in effect |
| `:IDEPin` | Record the live state as a new generation |
| `:IDERollback` | Return to the generation in effect |
| `:IDESwitch <generation>` | Switch to a stored generation |
| `:IDEExport [dir] [--history]` | Export the generation in effect |
| `:IDEAdd <owner/repo \| git URL>` | Declare and install a new plugin ([Plugins](#plugins)); `:IDEPin` locks it after you have tried it |
| `:IDESync` | Bring the plugins in line with the `LOCK`, fetch `rg`, `fd` and `fzf`, and rebuild parsers after a Neovim change (run for you after install and switches) |
| `:IDEUninstall` | Remove Super IDE; keep its state in the trash or delete it |
| `:ColumnGuidesToggle` / `On` / `Off` | Column guides |
| `:LspInfo` | Alias for `:checkhealth vim.lsp` |
| `:Mason`, `:Lazy` | Package and plugin managers |

From a terminal: `nvim -l init.lua install`, and with the installed file
(`~/.config/nvim/init.lua`): `update [vX.Y.Z]` (the same as `:IDEUpdate`),
`uninstall`, `help`.

```bash
nvim --clean file.c               # stock Neovim: no configuration, no plugins
NVIM_APPNAME=nvim-orig nvim       # your previous configuration (if you had one)
export EDITOR=nvim VISUAL=nvim    # in ~/.profile: crontab -e, sudoedit, … open Super IDE
```

---

## Languages

The first time you open a file of a language, the IDE sets that language up in
the background: syntax highlighting, language server, formatter. A tool you
installed yourself always wins; the rest comes through **Mason**, at its latest
version. To update a language tool later, or to go back to an older version,
use `:Mason`. The statusline shows `⟳ name` during downloads; later opens cost
nothing.

| Layer | Examples | Who provides it |
|:--|:--|:--|
| ① The compiler or interpreter you write code with | gcc, python3, cargo, go, php, your project's JDK | **You** |
| ② IDE tooling | every LSP server, formatter, debug adapter, `tree-sitter` CLI | **Super IDE, automatically**, via Mason |
| ③ Runtimes the tooling needs | Node.js LTS (web language servers), JDK 21 (jdtls) | **Super IDE, automatically**: portable builds on `PATH` for Neovim only |
| ④ System packages | C compiler, `unzip`, `python3-venv` | **You, with one keypress**: the command is proposed and runs only if you agree |

The portable JDK is given to jdtls only (via its `JAVA_HOME`); your projects
keep their own JDK. `ripgrep`, `fd` and `fzf` are installed during setup if
missing.

**Debug adapters** (codelldb, debugpy, delve) download on the first `<F5>` in a
language. `debug = false` in `SETTINGS` disables debugging.

| Language | Server | Formatter | Debug | Needs (layer ①/③) |
|:--|:--|:--|:--|:--|
| C / C++ / CUDA | clangd | clang-format | codelldb | Python (for Mason's clang-format, if you have no system one) |
| Python | basedpyright | ruff (fix + format) | debugpy | Python 3 with venv |
| Rust | rust-analyzer | rustfmt (from rustup) | codelldb | — |
| Go | gopls | goimports → gofmt | delve | Go |
| Java | jdtls | via jdtls | — | JDK 21 (auto), Python 3 (jdtls launcher) |
| JavaScript / TypeScript | vtsls + eslint | prettier | — | Node.js (auto) |
| HTML / JSP | html + emmet | prettier | — | Node.js (auto) |
| CSS / SCSS / Less | cssls | prettier | — | Node.js (auto) |
| PHP | intelephense | php-cs-fixer | — | PHP, Node.js (auto) |
| Assembly | asm-lsp | — | — | Cargo |
| Lua | lua_ls | stylua | — | — |
| Shell | bashls (+ shellcheck) | shfmt | — | Node.js (auto) |
| JSON / YAML | jsonls / yamlls | prettier | — | Node.js (auto) |
| TOML | taplo | taplo | — | — |
| Markdown | marksman | prettier | — | Node.js (auto) |
| CMake | neocmake | via LSP | — | — |
| Dockerfile | dockerls | — | — | Node.js (auto) |
| XML | lemminx | via LSP | — | — |
| SQL | — | sql-formatter | — | Node.js (auto) |
| Make, Vim script | — | — | — | — (highlighting only) |

- **Indentation**: 2 spaces by default; Python, Rust, Java and PHP use 4; Go uses
  tabs; Makefiles use real tabs. A project's `.editorconfig` always wins.
- **intelephense**'s free tier covers completion, diagnostics and navigation;
  renaming and some refactors need a licence.
- **basedpyright** runs with `typeCheckingMode = "standard"`.

### Adding a language

Add one row to the `LANGS` table in `init.lua`. For example, Zig:

```lua
zig = {
  label = "Zig", ft = { "zig" }, ts = { "zig" },
  lsp = { "zls" },
  tools = { { bin = "zls", mason = "zls", server = "zls" } },
  format = {},                 -- zls formats through the LSP fallback
  indent = { width = 4 },
},
```

Open a Zig file: its tools install the first time, as for every language.
Then `:IDEPin` keeps the edited `init.lua` as a new generation.

### Formatting on save

Saving formats a file only in a style its project has adopted, so an edit in
someone else's project never turns into a diff of every line:

| Formatter | Runs on save |
|:--|:--|
| gofmt / goimports, rustfmt | Always (one style per language) |
| stylua | With `.stylua.toml` or `stylua.toml` |
| clang-format | With `.clang-format` or `_clang-format` |
| prettier | With a Prettier config file, or a `"prettier"` key in `package.json` |
| ruff | With `ruff.toml`, `.ruff.toml`, or `[tool.ruff]` in `pyproject.toml` |
| taplo, php-cs-fixer, sql-formatter | With `taplo.toml`, `.php-cs-fixer(.dist).php`, `.sql-formatter.json` |
| shfmt | Never (it has no config file of its own) |
| Language server (Java) | With `.settings/org.eclipse.jdt.core.prefs` |

The config file is looked for in the file's folder and every folder above it.
The formatter then follows that file, not the editor's indentation settings.
`,f` formats the current file by hand at any time, with or without a config.

---

## Plugins

Pinned by the `LOCK`; a new release (`:IDEUpdate`) brings newer ones.

| Area | Plugins |
|:--|:--|
| Look | NeoSolarized (dark), lualine, which-key, indent-blankline, rainbow-delimiters, nvim-web-devicons |
| Finding | fzf-lua, neo-tree, oil, outline |
| Language | nvim-lspconfig, mason, nvim-treesitter, blink.cmp, LuaSnip, friendly-snippets, conform, neogen, nvim-autopairs, nvim-surround |
| Tools | toggleterm, vim-fugitive, gitsigns, persistence |
| Debug | nvim-dap, nvim-dap-ui, nvim-nio |

### Adding and removing plugins

Plugins are git repositories, mostly on GitHub (see awesome-neovim or dotfyle.com).

```vim
:IDEAdd folke/zen-mode.nvim           " or a full git URL
```

`:IDEAdd` verifies the repository, adds a spec between the `@@PLUGINS BEGIN` /
`@@PLUGINS END` markers in `init.lua` (keep the markers), installs the plugin
and opens the spec. Most Lua plugins need `setup()`: uncomment `opts = {}` and
add options from the plugin's documentation, then restart.

The plugin is **not locked** until `:IDEPin`. `:IDERollback` removes it again;
the edited `init.lua` is kept in `rejected/`.

To **remove** a plugin, delete its spec, restart and `:IDEPin`; `:IDESync`
deletes its directory.

---

## Settings

The `SETTINGS` table near the top of `init.lua`:

| Setting | Default | Meaning |
|:--|:--|:--|
| `leader` | `","` | Leader key |
| `format_on_save` | `true` | Initial state; toggle at runtime with `,tf`. Applies only where the project has adopted the formatter ([Formatting on save](#formatting-on-save)) |
| `debug` | `true` | Include debugging; adapters still download only on first `<F5>` |
| `auto_install` | `true` | Fetch tooling on first sight of a language |
| `python_provider` | `false` | Enable only for legacy remote plugins that need pynvim |
| `ui2` | `false` | Neovim 0.12's experimental message UI (removes "Press ENTER" prompts) |
| `github` | `https://github.com` | Mirror prefix for plugins, Mason downloads and portable tools |
| `github_raw` | `https://raw.githubusercontent.com` | Where `:IDEUpdate` downloads a release's `init.lua` from |
| `repo` | `smartcub/nvim-super-ide` | The repository whose releases `:IDEUpdate` follows |
| `neovim_releases` | `https://github.com/neovim/neovim/releases/download` | Where Neovim builds are downloaded from |
| `node_dist` | `https://nodejs.org/dist` | Mirror for the portable Node.js |
| `adoptium_api` | `https://api.adoptium.net` | Source of the portable JDK 21 |

Changing a setting counts as an *unpinned change* until `:IDEPin`. Do not edit
the `LOCK` table by hand; `:IDEPin` writes it.

---

## Files and directories

| | Linux / macOS | Windows |
|:--|:--|:--|
| config (`init.lua` only) | `~/.config/nvim` | `%LOCALAPPDATA%\nvim` |
| data (plugins, Mason, parsers, runtimes, generations, records) | `~/.local/share/nvim` | `%LOCALAPPDATA%\nvim-data` |
| state (sessions, undo, shada) | `~/.local/state/nvim` | `%LOCALAPPDATA%\nvim-data` |
| cache | `~/.cache/nvim` | `%TEMP%\nvim` |
| Neovim builds | `~/.local/opt/super-ide/nvim-<version>`, `current` → the live one | `%LOCALAPPDATA%\super-ide\…` (a junction for `current`) |
| the `nvim` command | `~/.local/bin/nvim` → `current/bin/nvim` | user `PATH` entry `…\super-ide\current\bin` |

(`XDG_CONFIG_HOME` and friends are honoured, as Neovim honours them.)

### Your previous configuration

On first install, existing Neovim directories are **renamed, never deleted**:

```
~/.config/nvim        ->  ~/.config/nvim-orig
~/.local/share/nvim   ->  ~/.local/share/nvim-orig
~/.local/state/nvim   ->  ~/.local/state/nvim-orig
~/.cache/nvim         ->  ~/.cache/nvim-orig
```

These are the directories of the application name `nvim-orig`, so the old
setup still runs:

```bash
NVIM_APPNAME=nvim-orig nvim     # your previous configuration, plugins and history
```

If both `nvim` and `nvim-orig` exist, the installer stops instead of
overwriting anything.

### clangd's index

In a C/C++ project the IDE makes `<project>/.cache` a link into
`~/.cache/nvim/clangd-index/`, so clangd's index stays out of your project, and
adds `/.cache` to `.git/info/exclude` (never committed). An existing real
`.cache` is left alone; uninstalling removes the links.

---

## Troubleshooting

Start with **`:IDEDoctor`**. Then:

| Symptom | Cause and fix |
|:--|:--|
| `nvim` still starts another Neovim after installing | Open a new terminal (or `hash -r`). Linux: log in again if `~/.local/bin` was new. Windows: a system-wide Neovim comes first on `PATH`; remove it ([What installing changes](#what-installing-changes)) |
| `install.ps1` "cannot be loaded because running scripts is disabled" | Start it with `powershell -ExecutionPolicy Bypass -File install.ps1` ([Local install](#local-install)) |
| An install printed `Nvim: Caught deadly signal 'SIGINT'` | Expected after Ctrl+C; the install was reverted ([Cancelling](#cancelling)) |
| `curl: (35) … SSL_ERROR_SYSCALL in connection to github.com:443`, or downloads that hang | GitHub cannot be reached from this network ([Network access](#network-access)) |
| The install stops at apt's "Waiting for cache lock" | Ubuntu's automatic updates hold the package lock (common right after a fresh install); the script waits up to 10 minutes |
| `:IDEUpdate` says "Unpinned changes" | It starts from a pinned state: `:IDEPin` keeps your changes, `:IDERollback` drops them; then run it again |
| `install.sh` says "no terminal to ask on" | It runs without a terminal (CI, cron): add `--yes` |
| The Neovim download fails with "GLIBC_2.xx not found" | This Linux is older than the official builds support; Ubuntu 22.04 or newer works |
| `:IDEPin` says to restart first | A candidate's Neovim is in place but not yet running; restart, try it, then pin |
| `:IDEExport` warns about unpinned changes | It exported the last pinned generation; `:IDEPin` first if the changes should travel |
| A language says “partly ready” | `:IDEDoctor` lists each problem under that language. Fix it, then `:IDEInstall <lang>` |
| Python never gets a language server | `python3-venv` is missing: `sudo apt install python3-venv`, then `:IDEInstall python` |
| “the Mason registry could not be downloaded” | Mason reaches `api.github.com`. Check the network; `:MasonUpdate` retries |
| A language tool's new version misbehaves | `:IDEDoctor` shows the installed version; `:MasonInstall name@version` installs an older one |
| A finder key (`f`, `r`, `g`, `<C-p>` …) says “fzf could not be downloaded” | The finders need the `fzf` program. Check the network and press the key again, or install `fzf` with your package manager |
| No syntax colours after a switch or update | Parsers are rebuilt for the new Neovim on the next start; this needs a C compiler. `:IDESync` retries |
| No language server for C/C++ | clangd needs `compile_commands.json` (below). On Linux arm64 Mason has no clangd; the IDE offers `apt-get install clangd` |
| `rust-analyzer` is “found” but does nothing | rustup's proxy exists without the component: `rustup component add rust-analyzer` |
| Copy over SSH does not reach your laptop | Your terminal must support OSC 52; in tmux set `set -g set-clipboard on` |

### `compile_commands.json` for C/C++

- CMake: `cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON …` (`<F7>` does this for you)
- Make: `bear -- make`
- Meson / Ninja: produced by default in the build directory

With no server attached, `<C-]>` falls back to `ctags -R` output.

---

## Authors

- **Rocky** — author
- ChatGPT
- Claude

## License

[MIT](LICENSE): free to use, modify and distribute, including commercially,
provided the copyright notice and license text are retained.

The license covers this repository only. Neovim, plugins and tools downloaded
by the IDE are under their own licenses.
