<#
.SYNOPSIS
  Build and run the winui3 test suite.

.DESCRIPTION
  A GUI test has two problems that a console test does not: it steals focus,
  and it cannot be checked by looking at pixels. This script solves the first;
  tests/tui.nim solves the second by asking the layout engine what it did
  rather than screenshotting the result.

  The app runs on a Windows desktop of its own (CreateDesktopW +
  CreateProcessW with STARTUPINFO.lpDesktop), so its window never appears on
  yours and never takes your keyboard.

  Note that synthetic mouse and keyboard input cannot reach a window on a
  desktop that is not the active input desktop — SetCursorPos there silently
  leaves the cursor at 0,0. That is why the tests drive controls through UI
  Automation instead.

.PARAMETER Seconds
  How long to wait for each suite before giving up. Each exits by itself via
  Application.Exit; the budget is generous because tsoak runs 60,000
  build-and-teardown cycles.

.PARAMETER Suites
  Which suites to run. The default is all of them. CI uses this to run a
  subset when the rest cannot work on a runner.

.PARAMETER BuildOnly
  Compile every suite and stop. Enough to catch a broken API on a machine
  that cannot host a window.
#>
param(
  [int]$Seconds = 300,
  [string[]]$Suites = @("tui", "tgenerated", "tstructs", "tlifetime",
                        "tgenerics", "terrors", "tsoak"),
  [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot
$bin = Join-Path $root "bin"

# No precondition about the runtime: building a suite stages it, because
# importing winui3 stages it. A clean checkout works.

# tleakhunt prints bytes-per-iteration rather than assertions, so it is built
# but not run — building it is what stops it rotting.
$alsoBuild = @("tleakhunt")

# Importing winui3 stages the SDK into the output directory and links the
# manifest, so there is nothing to set up here beyond saying where to build.
# That is the same path a consumer of this library gets.
foreach ($s in $Suites + $alsoBuild) {
  Write-Host "building $s..."
  nim c --path:(Join-Path $root "src") --outdir:$bin -d:release --hints:off `
    (Join-Path $PSScriptRoot "$s.nim")
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  $stale = Join-Path $bin "$s.exe.manifest"
  if (Test-Path $stale) { Remove-Item -LiteralPath $stale -Force }
}

if ($BuildOnly) { Write-Host ""; Write-Host "built, not run"; exit 0 }

Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public class Desk {
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 public static extern IntPtr CreateDesktopW(string n,IntPtr d,IntPtr dm,int f,uint a,IntPtr sa);
 [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr h);
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct STARTUPINFO {
  public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
  public int dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;
  public short wShowWindow; public short cbReserved2;
  public IntPtr lpReserved2,hStdInput,hStdOutput,hStdError; }
 [StructLayout(LayoutKind.Sequential)] public struct PROCESS_INFORMATION {
  public IntPtr hProcess,hThread; public int dwProcessId,dwThreadId; }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 public static extern bool CreateProcessW(string app,string cmd,IntPtr pa,IntPtr ta,
  bool inherit,uint flags,IntPtr env,string dir,ref STARTUPINFO si,out PROCESS_INFORMATION pi);
 [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
 [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
}
'@

$deskName = "winui3tests"
$desk = [Desk]::CreateDesktopW($deskName, [IntPtr]::Zero, [IntPtr]::Zero, 0, 0x01FF, [IntPtr]::Zero)
$shell = Join-Path $env:SystemRoot "System32\cmd.exe"
$overall = 0

foreach ($s in $Suites) {
  Write-Host ""
  Write-Host "=== $s ==="
  $exe = Join-Path $bin "$s.exe"
  $log = Join-Path $bin "$s.log"
  if (Test-Path $log) { Remove-Item $log -Force }
  # A window left over from an earlier run sits on the same desktop.
  Get-Process -Name $s -ErrorAction SilentlyContinue | Stop-Process -Force

  $si = New-Object Desk+STARTUPINFO
  $si.cb = [Runtime.InteropServices.Marshal]::SizeOf($si)
  $si.lpDesktop = $deskName
  $pi = New-Object Desk+PROCESS_INFORMATION

  # cmd.exe does the redirection, so the suite's output survives the run.
  # lpApplicationName must be a real path: PowerShell marshals $null as "",
  # which CreateProcessW rejects with ERROR_PATH_NOT_FOUND.
  $cmd = "cmd.exe /c `"`"$exe`" > `"$log`" 2>&1`""
  $ok = [Desk]::CreateProcessW($shell, $cmd, [IntPtr]::Zero, [IntPtr]::Zero,
                               $false, 0, [IntPtr]::Zero, $bin, [ref]$si, [ref]$pi)
  if (-not $ok) {
    Write-Error "CreateProcess failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
  }

  [Desk]::WaitForSingleObject($pi.hProcess, [uint32]($Seconds * 1000)) | Out-Null
  $code = 0
  [Desk]::GetExitCodeProcess($pi.hProcess, [ref]$code) | Out-Null
  Get-Process -Name $s -ErrorAction SilentlyContinue | Stop-Process -Force

  if (Test-Path $log) { Get-Content $log } else { Write-Host "(no output)" }

  # 259 is STILL_ACTIVE: the suite never finished, which is a failure.
  if ($code -eq 259) { Write-Host "TIMED OUT after $Seconds seconds"; $code = 1 }
  if ($code -ne 0) {
    Write-Host ("  [" + $s + " exited with " + $code + " (0x" + $code.ToString('X8') + ")]")
    $overall = $code
  }
}

[Desk]::CloseDesktop($desk) | Out-Null
exit $overall
