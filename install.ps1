<#
============================================================================
 Neovim Super IDE — first-time setup for Windows 10 / 11
============================================================================

 Usage, from the folder holding this script and init.lua:
     powershell -ExecutionPolicy Bypass -File install.ps1 [--yes] [--git-editor]
 "-ExecutionPolicy Bypass" applies to this one run only; Windows refuses
 unsigned script files by default, and nothing is changed permanently.

 Usage without any files, in a PowerShell window:
     irm https://raw.githubusercontent.com/smartcub/nvim-super-ide/main/install.ps1 | iex
 init.lua and both scripts are downloaded from the repository first.
 `irm | iex` cannot pass options; with options, use:
     & ([scriptblock]::Create((irm <the same URL>))) --yes

 Environment (both optional):
   SUPER_IDE_REPO   GitHub repository to download from (smartcub/nvim-super-ide)
   SUPER_IDE_BASE   full base URL instead, e.g. a mirror or a fork's branch
                    (https://raw.githubusercontent.com/$SUPER_IDE_REPO/main)

 What it does, in order:
   0. Started without init.lua beside it: downloads init.lua, install.sh and
      install.ps1 from the repository into a temporary folder.
   1. Reads the pinned Neovim version from init.lua's LOCK block.
   2. Installs the missing system packages with winget, after asking:
        Git.Git            git (required: plugins)
        LLVM.LLVM          clang, for Tree-sitter parsers
        Python.Python.3.12 Python with venv, for Mason's Python-based tools
      curl.exe and tar.exe ship with Windows 10 (1803) and later.
   3. Downloads that exact Neovim release into the temporary folder
      (skipped when Super IDE already has that version installed).
   4. Runs it as the installer: `nvim -l init.lua install --archive FILE`.
      From here on init.lua does everything: it unpacks the same archive
      into %LOCALAPPDATA%\super-ide (no second download), sets aside your
      existing configuration, adds the user PATH entry, installs plugins, ...
   5. Deletes the temporary folder, whatever happened.

 This script does only what cannot be done before a Neovim exists.
 Everything else lives in init.lua, once, for every platform.
 No uninstall here: winget packages stay (other software may use them);
 uninstall with  nvim -l $env:LOCALAPPDATA\nvim\init.lua uninstall

 Safe to run again: present packages are skipped.
 Written for Windows PowerShell 5.1, the one every Windows 10/11 has.
============================================================================
#>

# Run as a file (-File install.ps1), MyCommand.Path is this script's path.
# Run from `irm | iex` or a script block it is empty: the code then runs in
# your own PowerShell session, which shapes the whole layout below.
$SuperIdeFile = $MyInvocation.MyCommand.Path

# The body runs in a child scope (& { ... }): nothing it defines stays behind
# in your session. It never calls `exit`, which under `iex` would close your
# PowerShell window: errors are thrown and caught at its end instead. The
# options (init.lua's: --yes, --git-editor) arrive as $args, unchanged.
& {
  $ErrorActionPreference = 'Stop'
  $Opts = @($args)
  $Yes = ($Opts -contains '--yes') -or ($Opts -contains '-y')

  function Say ($m)  { Write-Host "==> $m" }
  function Warn ($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
  function Die ($m)  { throw $m }   # caught at the end of this block
  function Have ($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }
  function Ask ($q) {
    if ($Yes) { return $true }
    $r = Read-Host "??  $q [Y/n]"
    return ($r -eq '' -or $r -match '^(y|yes)$')
  }

  # Run the installer and wait for it; its exit code is returned. The
  # installer handles Ctrl+C itself: it puts back everything it changed, then
  # exits (init.lua, "Cancel and roll back"). So it is started with
  # Start-Process, not `&`, and kept in $Runner: `finally` below waits for it
  # before it deletes $Tmp, whatever stopped this script.
  $Runner = $null
  function Invoke-Installer ([string]$Exe, [string[]]$Arguments) {
    # Start-Process joins the arguments with spaces; quoting each one keeps a
    # path with spaces in it (a user name, %TEMP%) whole.
    $quoted = @($Arguments | ForEach-Object { '"' + $_ + '"' })
    $p = Start-Process -FilePath $Exe -ArgumentList $quoted -NoNewWindow -PassThru
    $null = $p.Handle   # keeps the process handle open, or ExitCode stays empty
    Set-Variable -Name Runner -Value $p -Scope 1
    $p.WaitForExit()
    return $p.ExitCode
  }

  # A program winget just installed is on the *registry* PATH, not on this
  # session's: reload it, Machine first, the order Windows itself uses.
  function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
  }

  # Temporary folder: outside your profile, so a failure leaves it untouched;
  # removed in `finally`, success or not. It holds the downloaded files
  # (step 0) and the Neovim that runs the installer (step 3).
  $Tmp = Join-Path ([IO.Path]::GetTempPath()) ("super-ide-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Path $Tmp | Out-Null
  $code = 1
  try {
    # --- 0. Where init.lua comes from ----------------------------------------
    # Beside this file when run as a file; downloaded otherwise. The test is on
    # this script's own path, never on the current folder, so an unrelated
    # init.lua there is never installed by accident.
    $Repo = if ($env:SUPER_IDE_REPO) { $env:SUPER_IDE_REPO } else { 'smartcub/nvim-super-ide' }
    $Base = if ($env:SUPER_IDE_BASE) { $env:SUPER_IDE_BASE } else { "https://raw.githubusercontent.com/$Repo/main" }
    if ($SuperIdeFile -and (Split-Path -Leaf $SuperIdeFile) -eq 'install.ps1') {
      $Here = Split-Path -Parent $SuperIdeFile
      if (-not (Test-Path (Join-Path $Here 'init.lua'))) { Die "init.lua not found beside this script ($Here)" }
    } else {
      if (-not (Have 'curl.exe')) { Die 'curl.exe is missing; it ships with Windows 10 1803 and later' }
      $Here = Join-Path $Tmp 'src'
      New-Item -ItemType Directory -Path $Here | Out-Null
      Say "Downloading Super IDE from $Base …"
      # The scripts come along so the installer keeps them for :IDEExport.
      foreach ($f in 'init.lua', 'install.sh', 'install.ps1') {
        & curl.exe -fsSL --retry 2 -o (Join-Path $Here $f) "$Base/$f"
        if ($LASTEXITCODE -ne 0) { Die "download failed: $Base/$f" }
      }
    }
    $Init = Join-Path $Here 'init.lua'

    # --- 1. The Neovim this file pins ----------------------------------------
    $text = Get-Content -Raw -Path $Init
    # Only the LOCK block is searched (machine-written by :IDEPin, fixed
    # layout), so a "neovim = ..." line elsewhere cannot be mistaken for the
    # pin. -match fills the automatic variable $Matches; (?s) lets "." span lines.
    if ($text -notmatch '(?s)-- @@LOCK BEGIN(.*?)-- @@LOCK END') { Die "$Init has no LOCK block; is it a Super IDE init.lua?" }
    if ($Matches[1] -notmatch '(?m)^\s*neovim\s*=\s*"(v\d+\.\d+\.\d+)"') { Die 'no Neovim version in the LOCK block' }
    $Tag = $Matches[1]

    # Releases from SETTINGS.neovim_releases, so a mirror set there applies here.
    $Releases = 'https://github.com/neovim/neovim/releases/download'
    if ($text -match '(?m)^\s*neovim_releases\s*=\s*"([^"]+)"') { $Releases = $Matches[1] }

    $Asset = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'nvim-win-arm64.zip' } else { 'nvim-win64.zip' }
    Say "Preparing this machine for Neovim Super IDE (Neovim $Tag, windows/$($env:PROCESSOR_ARCHITECTURE))"

    # --- 2. System packages --------------------------------------------------
    # The same list init.lua's installer checks (check_system).
    # winget's LLVM leaves clang off PATH; init.lua looks in this folder itself.
    $LlvmBin = Join-Path $env:ProgramFiles 'LLVM\bin'
    function Have-CC { (Have clang) -or (Have gcc) -or (Have cl) -or (Test-Path (Join-Path $LlvmBin 'clang.exe')) }
    # Windows ships a "python.exe" stub that only opens the Microsoft Store, so
    # test that Python really runs and has venv, not merely that it is on PATH.
    # python3 or python, as init.lua and Mason look for them; the `py`
    # launcher alone does not count, because Mason never calls it.
    function Have-Venv {
      foreach ($py in 'python3', 'python') {
        if (Have $py) {
          & $py -c 'import ensurepip, venv' 2>$null | Out-Null
          if ($LASTEXITCODE -eq 0) { return $true }
        }
      }
      return $false
    }

    $packages = @(
      @{ Name = 'git';           Id = 'Git.Git';            Test = { Have git };  Required = $true },
      @{ Name = 'a C compiler';  Id = 'LLVM.LLVM';          Test = { Have-CC };   Required = $false },
      @{ Name = 'Python (venv)'; Id = 'Python.Python.3.12'; Test = { Have-Venv }; Required = $false }
    )
    foreach ($tool in 'curl.exe', 'tar.exe') {
      if (-not (Have $tool)) { Die "$tool is missing; it ships with Windows 10 1803 and later" }
    }
    $missing = @($packages | Where-Object { -not (& $_.Test) })
    if ($missing.Count -gt 0) {
      Say ('Missing: ' + (($missing | ForEach-Object { $_.Name }) -join ', '))
      if (-not (Have winget)) {
        Die 'winget is not available: update "App Installer" in the Microsoft Store, then run this again'
      }
      foreach ($p in $missing) {
        $cmd = "winget install -e --id $($p.Id)"
        if (Ask "Install $($p.Name) ($cmd)?") {
          # With --yes nobody reads winget's agreement prompts, so accept them
          # up front; otherwise winget shows them and you answer.
          $extra = if ($Yes) { @('--accept-source-agreements', '--accept-package-agreements') } else { @() }
          & winget install -e --id $p.Id @extra
          if ($LASTEXITCODE -ne 0) { Warn "winget reported an error for $($p.Id)" }
        }
      }
      Refresh-Path
      foreach ($p in $missing) {
        if (-not (& $p.Test)) {
          if ($p.Required) { Die "$($p.Name) is required; install it, open a new terminal and run this again" }
          if ($p.Id -like 'Python*') {
            Warn 'Python is installed but not on PATH: in "Apps > Installed apps", Modify Python and tick "Add Python to environment variables".'
          }
          Warn "Continuing without $($p.Name); README.md (section 2) says what it is for."
        }
      }
    }

    # --- 3. A Neovim to run the installer ------------------------------------
    # Already installed (a re-run, or importing a new init.lua): use the pinned
    # build init.lua keeps, and download nothing. The path must match DIR.opt
    # in init.lua (section 2).
    $Installed = Join-Path $env:LOCALAPPDATA "super-ide\nvim-$Tag\bin\nvim.exe"
    if (Test-Path $Installed) {
      Say "Neovim $Tag is already installed; using it."
      $code = Invoke-Installer $Installed (@('-l', $Init, 'install') + $Opts)
    } else {
      $Zip = Join-Path $Tmp $Asset
      $Url = "$Releases/$Tag/$Asset"
      Say "Downloading Neovim $Tag ($Asset) …"
      # curl.exe rather than Invoke-WebRequest: much faster on PowerShell 5.1,
      # and the same tool init.lua uses later.
      & curl.exe -fL --retry 2 --progress-bar -o $Zip $Url
      if ($LASTEXITCODE -ne 0) { Die "download failed: $Url" }
      $Unpacked = Join-Path $Tmp 'nvim'
      New-Item -ItemType Directory -Path $Unpacked | Out-Null
      # Windows' tar.exe (bsdtar) reads zip files too.
      & tar.exe -xf $Zip -C $Unpacked --strip-components=1
      if ($LASTEXITCODE -ne 0) { Die "unpacking $Asset failed" }

      # --- 4. Hand over to init.lua --------------------------------------------
      # The installer reads the same archive, so nothing is downloaded twice.
      # The Neovim running it lives in the temporary folder, never in the place
      # it installs to, so no running program blocks any file it replaces.
      $code = Invoke-Installer (Join-Path $Unpacked 'bin\nvim.exe') (@('-l', $Init, 'install', '--archive', $Zip) + $Opts)
    }
  }
  catch {
    Write-Host "xx  $_" -ForegroundColor Red
    $code = 1
  }
  finally {
    # After Ctrl+C the installer may still be putting things back; it runs the
    # Neovim in $Tmp, which cannot be deleted while it runs. Wait for it.
    if ($Runner -and -not $Runner.HasExited) { $Runner.WaitForExit() }
    Remove-Item -Recurse -Force -Path $Tmp -ErrorAction SilentlyContinue
  }
  # The result, for whoever started us: as $LASTEXITCODE in your session, and
  # as the exit code below when run as a file.
  $global:LASTEXITCODE = $code
} @args

if ($SuperIdeFile) { exit $global:LASTEXITCODE }
