#!/bin/sh
# ============================================================================
#  Neovim Super IDE — first-time setup for Linux and macOS
# ============================================================================
#
#  Usage:   sh install.sh [--yes] [--git-editor]
#               installs the init.lua beside this script
#           curl -fsSL https://raw.githubusercontent.com/smartcub/nvim-super-ide/main/install.sh | sh
#               no files needed: init.lua and both scripts are downloaded
#               from the repository first. Options go after `sh -s --`:
#               ... | sh -s -- --yes
#
#  Environment (all optional):
#    SUPER_IDE_REF    what to download: a release tag such as v1.2.0, or a
#                     branch (main, the default)
#    SUPER_IDE_REPO   GitHub repository to download from (smartcub/nvim-super-ide)
#    SUPER_IDE_BASE   full base URL instead, e.g. a mirror
#                     (https://raw.githubusercontent.com/$SUPER_IDE_REPO/$SUPER_IDE_REF)
#
#  What it does, in order:
#    0. Piped from curl (no init.lua beside it): downloads init.lua,
#       install.sh and install.ps1 from the repository into a temporary
#       directory, and installs from there.
#    1. Reads the pinned Neovim version from init.lua's LOCK block.
#    2. Installs the missing system packages:
#         Ubuntu / Debian (also WSL): apt-get, after showing the command and
#                                     asking (sudo asks for your password);
#         macOS:   Apple's Command Line Tools (git, clang, python3);
#         others:  names what is missing and stops if a required one is.
#    3. Downloads that exact Neovim release into a temporary directory
#       (skipped when Super IDE already has that version installed).
#    4. Runs it as the installer: `nvim -l init.lua install --archive FILE`.
#       From here on init.lua does everything: it unpacks the same archive
#       into ~/.local/opt/super-ide (no second download), sets aside your old
#       configuration, installs plugins, and so on. See README.md.
#    5. Deletes the temporary directory, whatever happened.
#
#  The division of labour: this script does only what cannot be done before
#  a Neovim exists — system packages need the system's own tools, and a
#  Neovim is needed to run init.lua at all. Everything else lives in
#  init.lua, so the logic exists once, for every platform.
#
#  What it does NOT do:
#    * No full system upgrade (apt upgrade). It is slow, touches unrelated
#      software and is your decision, not an IDE's.
#    * No uninstall. System packages stay when Super IDE goes: they may have
#      been here before, or other software may use them. Uninstall with
#      `nvim -l ~/.config/nvim/init.lua uninstall`.
#    * No PATH or profile change; init.lua makes the `nvim` command.
#
#  Safe to run again: present packages are skipped; a run cut off by a
#  network error simply starts over.
#
#  Written for POSIX sh (dash on Ubuntu, bash 3.2 on macOS): no bashisms.
# ============================================================================

set -eu

say()  { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { printf 'xx  %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Everything below runs inside main(), called on the last line. Piped from
# curl, sh reads this script from the pipe as it goes; a function body is read
# completely before any of it runs, so nothing that follows can be cut off or
# read by a program started on the way. (The body is not indented, to keep it
# readable as a plain script.)
main() {

# --- Options -------------------------------------------------------------------
# All options go on to the installer unchanged; --yes is also honoured here,
# for the package prompt.
YES=0
for a in "$@"; do
  case "$a" in
    --yes|-y) YES=1 ;;
    --help|-h)
      # The help is this file's header comment. Piped from curl there is no
      # file to read it from ($0 is then "sh"), so point to the repository.
      if [ -f "$0" ]; then sed -n '2,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      else echo "Neovim Super IDE installer: see README.md in the repository."; fi
      exit 0 ;;
  esac
done

# Ask a yes/no question, default yes. The answer is read from the terminal
# itself (/dev/tty), not from stdin, so it still works when stdin is a pipe.
ask() {
  [ "$YES" = 1 ] && return 0
  # Try to open it: `[ -r /dev/tty ]` is true even without a controlling
  # terminal (cron, setsid, CI), where the open itself then fails.
  ( : </dev/tty ) 2>/dev/null || die "no terminal to ask on; run again with --yes to accept the defaults"
  printf '??  %s [Y/n] ' "$1"
  read -r reply </dev/tty || reply=n
  case "$reply" in ''|y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Programs started below must read answers from the terminal, never from
# stdin: piped from curl, stdin is the pipe. With no terminal at all (CI,
# --yes runs) they read nothing and take their defaults.
if ( : </dev/tty ) 2>/dev/null; then TTY=/dev/tty; else TTY=/dev/null; fi

# --- Temporary directory --------------------------------------------------------
# Outside $HOME, so a failure leaves your home directory untouched; removed on
# every exit, success or not. It holds the downloaded files (step 0) and the
# Neovim that runs the installer (step 3).
TMP=$(mktemp -d "${TMPDIR:-/tmp}/super-ide.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
# A signal leaves through the EXIT trap, so cleanup still runs: INT (Ctrl-C),
# TERM, HUP (terminal closed), PIPE (output piped into something that quit).
trap 'exit 130' INT TERM HUP PIPE

# --- 0. Where init.lua comes from ------------------------------------------------
# Run as a file (sh install.sh), $0 is this script's path and init.lua must be
# beside it. Piped from curl, $0 is just "sh": there is no "beside", so fetch
# the files. The test is on $0 itself, never on the current directory: an
# unrelated init.lua there must not be installed by accident.
REPO="${SUPER_IDE_REPO:-smartcub/nvim-super-ide}"
BASE="${SUPER_IDE_BASE:-https://raw.githubusercontent.com/$REPO/${SUPER_IDE_REF:-main}}"
if [ -f "$0" ] && [ "$(basename "$0")" = install.sh ]; then
  HERE=$(cd "$(dirname "$0")" && pwd)
  [ -f "$HERE/init.lua" ] || die "init.lua not found beside this script ($HERE)"
else
  have curl || die "curl is needed to download Super IDE"
  HERE="$TMP/src"
  mkdir "$HERE"
  say "Downloading Super IDE from $BASE …"
  # The scripts come along so the installer keeps them for :IDEExport.
  for f in init.lua install.sh install.ps1; do
    curl -fsSL --retry 2 -o "$HERE/$f" "$BASE/$f" || die "download failed: $BASE/$f"
  done
fi
INIT="$HERE/init.lua"

# --- 1. The file to install, and the Neovim it pins ---------------------------

# Only the LOCK block is searched, so a "neovim = ..." line elsewhere in the
# file cannot be mistaken for the pin. The block is machine-written by
# :IDEPin, so its layout is fixed: `  neovim = "vX.Y.Z",`.
TAG=$(sed -n '/^-- @@LOCK BEGIN/,/^-- @@LOCK END/s/^ *neovim *= *"\(v[0-9][0-9.]*\)".*/\1/p' "$INIT" | head -n 1)
[ -n "$TAG" ] || die "no Neovim version in the LOCK block of $INIT; is it a Super IDE init.lua?"

# Where releases come from: SETTINGS.neovim_releases in init.lua, so a mirror
# set there applies here too. GitHub when the line is not found.
RELEASES=$(sed -n 's/^ *neovim_releases *= *"\([^"]*\)".*/\1/p' "$INIT" | head -n 1)
[ -n "$RELEASES" ] || RELEASES="https://github.com/neovim/neovim/releases/download"

# Release asset names, as published by the Neovim project (0.10.4 and later).
case "$(uname -s)" in
  Linux)  OS=linux ;;
  Darwin) OS=macos ;;
  *) die "unsupported system $(uname -s); on Windows use install.ps1" ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "no official Neovim build for CPU $(uname -m)" ;;
esac
ASSET="nvim-$OS-$ARCH.tar.gz"
say "Preparing this machine for Neovim Super IDE (Neovim $TAG, $OS/$ARCH)"

# --- 2. System packages ----------------------------------------------------------
# The same list init.lua's installer checks (check_system), so it finds
# nothing missing afterwards. Each entry: test, then the apt package.
#   git, curl, tar  required: plugins, downloads, unpacking
#   unzip           Mason unpacks zip releases with it
#   C compiler      Tree-sitter parsers are compiled C
#   python3 + venv  Mason puts Python-based tools in virtual environments;
#                   stock Ubuntu ships python3 without the venv module
#   clipboard tool  only inside a graphical session (the "+ register)
missing_required=""
missing_apt=""
need() { missing_apt="$missing_apt $1"; }

have git  || { need git;  missing_required="$missing_required git"; }
have curl || { need curl; missing_required="$missing_required curl"; }
have tar  || { need tar;  missing_required="$missing_required tar"; }
have unzip || need unzip
have cc || have gcc || have clang || need build-essential
if have python3; then
  python3 -c 'import ensurepip, venv' >/dev/null 2>&1 || need python3-venv
else
  need python3; need python3-venv
fi
if [ "$OS" = linux ]; then
  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    have wl-copy || need wl-clipboard
  elif [ -n "${DISPLAY:-}" ]; then
    have xclip || have xsel || need xclip
  fi
fi

if [ "$OS" = macos ]; then
  # git, clang, make and python3 (with venv) all come with Apple's Command
  # Line Tools; curl, tar and unzip are part of macOS. Homebrew is not needed.
  if ! xcode-select -p >/dev/null 2>&1; then
    say "Apple's Command Line Tools are missing (git, the C compiler, python3)."
    if ask "Start Apple's installer for them now (xcode-select --install)?"; then
      xcode-select --install || true
      die "Finish that installation in its window, then run this script again."
    fi
    die "The Command Line Tools are required."
  fi
elif [ -n "$missing_apt" ]; then
  if have apt-get; then
    # Root (a container, a fresh WSL) needs no sudo; anyone else does.
    if [ "$(id -u)" = 0 ]; then SUDO=""
    elif have sudo; then SUDO="sudo "
    else die "missing:$missing_apt, and sudo is not available to install them"; fi
    # DPkg::Lock::Timeout: on a fresh Ubuntu, unattended-upgrades often holds
    # the package lock for minutes after first boot; wait instead of failing.
    APT="${SUDO}apt-get -o DPkg::Lock::Timeout=600"
    CMD="$APT update && $APT install -y$missing_apt"
    say "Missing:$missing_apt"
    say "Proposed: $CMD"
    if ask "Run it now?"; then
      # sh -c, so `sudo` asks for the password on this terminal.
      sh -c "$CMD" <"$TTY" || die "the package installation failed (see above)"
    elif [ -n "$missing_required" ]; then
      die "required:$missing_required"
    fi
  else
    # Another distribution: package names differ, so name what is missing
    # (in Debian's spelling) and let you install it the local way.
    warn "Missing (Debian package names):$missing_apt"
    [ -z "$missing_required" ] || die "install at least$missing_required with your package manager, then run this again"
    warn "Continuing without them; README.md (section 2) says what each one is for."
  fi
fi

# --- 3. A Neovim to run the installer ------------------------------------------
# Already installed (a re-run, or importing a new init.lua): the pinned build
# init.lua keeps in ~/.local/opt/super-ide is the right one, so use it and
# download nothing. The path must match DIR.opt in init.lua (section 2).
INSTALLED="$HOME/.local/opt/super-ide/nvim-$TAG/bin/nvim"
if [ -x "$INSTALLED" ]; then
  say "Neovim $TAG is already installed; using it."
  set +e
  "$INSTALLED" -l "$INIT" install "$@" <"$TTY"
  exit $?
fi

# Otherwise download it into the temporary directory.

URL="$RELEASES/$TAG/$ASSET"
say "Downloading Neovim $TAG ($ASSET) …"
curl -fL --retry 2 --progress-bar -o "$TMP/$ASSET" "$URL" || die "download failed: $URL"
mkdir "$TMP/nvim"
tar -xzf "$TMP/$ASSET" -C "$TMP/nvim" --strip-components=1 || die "unpacking $ASSET failed"
# (No Gatekeeper step on macOS: only browser downloads get the quarantine
# flag, curl's do not. init.lua clears it anyway when it unpacks.)

# --- 4. Hand over to init.lua ------------------------------------------------------
# Run as a child, not with exec, so the cleanup trap above still fires.
# --archive: the installer unpacks this same file, so nothing is downloaded twice.
set +e
"$TMP/nvim/bin/nvim" -l "$INIT" install --archive "$TMP/$ASSET" "$@" <"$TTY"
code=$?
set -e
if [ "$code" -ne 0 ] && [ "$OS" = linux ]; then
  # The official Linux builds need a reasonably recent glibc. A system older
  # than that fails right at start, with "GLIBC_2.xx not found" above.
  warn "If the error above mentions GLIBC, this Linux is too old for the official Neovim builds."
fi
exit "$code"
}

main "$@"
