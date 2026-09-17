## Putting the Windows App SDK next to your executable, without being asked.
##
## A WinUI 3 app needs two things beside it that are nothing to do with your
## code: the SDK's DLLs, and a manifest naming every class they activate.
## Doing that by hand is the worst part of this library, so it happens at
## compile time and you never see it — `import winui3` and build.
##
## This is what `cargo build` does for the Rust `windows-reactor` crate, whose
## `setup` crate downloads the runtime and copies it beside the binary. The
## same 50-odd megabytes end up in the output directory either way; the only
## question is whether a person has to move them.
##
## ## How
##
## The framework package is already staged on the machine — on a stock
## Windows 11 the inbox Photos app depends on it — so the files exist and are
## readable under `C:\Program Files\WindowsApps`. PowerShell says where, and
## `robocopy` copies what is missing or stale. After the first build there is
## nothing to do and it costs a fraction of a second.
##
## ## Opting out
##
## `-d:winui3NoAutoStage` if you would rather stage the runtime yourself, or
## are building something that imports this library without shipping a GUI.

import std/os
import winrt/core

const
  AutoStage* = not defined(winui3NoAutoStage)

  ManifestResource* = currentSourcePath.parentDir / "app.res"
    ## The compiled `RT_MANIFEST` carrying ~1840 `activatableClass` entries.
    ##
    ## It is linked rather than copied beside the executable because Windows
    ## caches the activation context by executable path *and timestamp*,
    ## including the result when no manifest was found — so an external
    ## `.exe.manifest` that appears after the first run changes nothing until
    ## the binary is rebuilt, and that failure looks exactly like a broken
    ## manifest. A resource cannot be got wrong that way.

## The payload, named rather than globbed.
##
## The installed framework package holds about 105 MB, and most of it is not
## WinUI: `onnxruntime.dll` and `DirectML.dll` alone are 38 MB of machine
## learning that a button does not need. This is the set the test suite
## actually exercises — Fluent theming, Mica, layout, events and UI
## Automation all pass against exactly these files.
##
## Naming them also makes a missing one loud: a glob would silently ship
## whatever a future SDK happened to include, or silently stop shipping
## something it renamed.
const RuntimeFiles* = [
  "CoreMessagingXP.dll",
  "DWriteCore.dll",
  "DwmSceneI.dll",
  "MRM.dll",
  "Microsoft.DirectManipulation.dll",
  "Microsoft.Graphics.Imaging.dll",
  "Microsoft.InputStateManager.dll",
  "Microsoft.Internal.FrameworkUdk.dll",
  "Microsoft.UI.Composition.OSSupport.dll",
  "Microsoft.UI.Input.dll",
  "Microsoft.UI.Windowing.Core.dll",
  "Microsoft.UI.Windowing.dll",
  "Microsoft.UI.Xaml.Controls.dll",
  "Microsoft.UI.Xaml.Controls.pri",
  "Microsoft.UI.Xaml.Internal.dll",
  "Microsoft.UI.Xaml.Phone.dll",
  "Microsoft.UI.dll",
  "Microsoft.UI.pri",
  "Microsoft.Windows.ApplicationModel.Resources.dll",
  "Microsoft.WindowsAppRuntime.dll",
  "Microsoft.WindowsAppRuntime.pri",
  "Microsoft.ui.xaml.dll",
  "Microsoft.ui.xaml.resources.19h1.dll",
  "Microsoft.ui.xaml.resources.common.dll",
  "SessionHandleIPCProxyStub.dll",
  "WinUIEdit.dll",
  "dcompi.dll",
  "dwmcorei.dll",
  "marshal.dll",
  "resources.pri",
  "wuceffectsi.dll",
]

when AutoStage:
  # Only the staging half needs these, and `-d:winui3NoAutoStage` should not
  # pay for an import it does not use.
  import std/[compilesettings, strutils]

  proc stageRuntime() {.compileTime.} =
    ## Copy the SDK beside whatever is being built.
    let dest = querySetting(SingleValueSetting.outDir)
    if dest.len == 0:
      return

    # Where Windows staged the framework package. Asking the package manager
    # beats guessing at a path: the directory name carries both the version
    # and a publisher hash.
    let src = staticExec(
      "powershell -NoProfile -NonInteractive -Command " &
      "\"(Get-AppxPackage -Name Microsoft.WindowsAppRuntime.2 | " &
      "Where-Object { $_.Architecture -eq 'X64' } | " &
      "Select-Object -First 1).InstallLocation\"").strip()

    if src.len == 0:
      # Not fatal at compile time: the build should still succeed, and the
      # error the app gives at startup says exactly what is missing and where
      # it looked.
      echo "winui3: no Microsoft.WindowsAppRuntime.2 package found, so the " &
           "SDK was not staged.\n" &
           "        The build will succeed and the app will not start. " &
           "Install the Windows\n" &
           "        App SDK runtime, or see Deployment in the README."
      return

    # /NJH /NJS /NP /NFL /NDL: no header, summary, progress or file lists —
    # robocopy is chatty and this should be silent. It also skips files that
    # are already current, so every build after the first costs nothing.
    var files = ""
    for f in RuntimeFiles:
      files.add " \"" & f & "\""
    discard staticExec("robocopy \"" & src & "\" \"" & dest & "\"" & files &
                       " /NJH /NJS /NP /NFL /NDL /R:1 /W:1")

  static:
    stageRuntime()

  # Embed the manifest. Both halves of deployment are now automatic.
  {.passL: ManifestResource.}

# ------------------------------------------------- when it goes wrong anyway

proc winuiHint(classId: string): string =
  ## What `REGDB_E_CLASSNOTREG` means for a WinUI class, in terms someone can
  ## act on.
  ##
  ## `winrt` cannot say this for itself: for an inbox Windows class the answer
  ## would be different, and for most of them the error cannot happen at all.
  ## Here it has one cause — the SDK is not beside the executable, or the
  ## manifest naming its classes is not in the executable — and the fix differs
  ## depending on which. Guessing wrongly costs an afternoon, so it says both.
  let exe = getAppFilename()
  let dir = exe.parentDir
  let manifest = exe & ".manifest"
  "\n\nwinui3: " & classId & " could not be activated.\n" &
    "WinUI 3 is not part of Windows; a process reaches it through the Windows\n" &
    "App SDK runtime staged beside the executable, named by a manifest.\n\n" &
    "  executable: " & exe & "\n" &
    "  manifest:   " & manifest &
    (if fileExists(manifest): "  (present, and the embedded one may differ)"
     else: "  (none, so the embedded one is in use)") & "\n" &
    "  SDK DLLs:   " & dir &
    (if fileExists(dir / "Microsoft.UI.Xaml.dll"): "  (present)"
     else: "  (MISSING Microsoft.UI.Xaml.dll)") & "\n\n" &
    "Staging happens at compile time, so the usual cause is that the build\n" &
    "could not find an installed Windows App SDK runtime to stage from — the\n" &
    "compiler prints a message saying so. Windows also caches the activation\n" &
    "context by executable path and timestamp, including the result when\n" &
    "nothing was found, so a fix only takes effect once the executable is\n" &
    "rebuilt.\n\n" &
    "See Deployment in README.md."

activationHint = winuiHint
