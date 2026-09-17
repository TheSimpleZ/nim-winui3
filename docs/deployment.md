# Deployment, in detail

The short version is in the README: write a file, `nim c -r` it, ship the
folder. This is what that does.

## Why anything is needed at all

WinUI 3 is not part of Windows. It ships in the Windows App SDK, and a process
reaches it in one of two ways: as a packaged (MSIX) app with a framework
dependency, or *registration-free*, with the SDK's DLLs sitting beside the
executable and a manifest naming the classes they activate. This library does
the second, because the first needs a signing certificate and an installer and
is a different project.

So an app needs two things that have nothing to do with its own code:

1. about 31 files of Windows App SDK runtime in its output directory, and
2. an `RT_MANIFEST` listing ~1,840 `activatableClass` entries.

Both happen when you build, from `import winui3`.

## Staging the runtime

`src/winui3/deploy.nim` runs at compile time, inside a `static:` block.

```
querySetting(outDir)                      where the executable is going
  ↓
Get-AppxPackage Microsoft.WindowsAppRuntime.2 (x64)   where the SDK already is
  ↓
robocopy <package> <outDir> <31 named files>          copy what is missing
```

**The source is a framework package Windows has already staged**, under
`C:\Program Files\WindowsApps`, so there is no download. On a stock Windows 11
it is present because the inbox Photos app depends on it. Asking the package
manager beats guessing at a path: the directory name carries both the version
and a publisher hash.

**The files are named, not globbed.** The installed framework package holds
about 105 MB and most of it is not WinUI — `onnxruntime.dll` and `DirectML.dll`
alone are 38 MB of machine learning that a button does not need. The list in
`RuntimeFiles` is the set the test suite actually exercises: Fluent theming,
Mica, layout, events and UI Automation all pass against exactly these files.
Naming them also makes a missing one loud, where a glob would silently ship
whatever a future SDK happened to include, or silently stop shipping something
it renamed.

**It is incremental.** `robocopy` skips files that are already current, so every
build after the first costs a fraction of a second. The flags `/NJH /NJS /NP
/NFL /NDL` suppress its header, summary, progress and file lists, because a
build should be quiet.

**A missing SDK is not a build error.** If no framework package is found the
compiler prints what is missing and where it looked, and the build succeeds.
The app will then fail to start, with an error that says the same thing —
failing the build instead would mean a library that cannot be type-checked on a
machine without the SDK, which is a worse trade.

## The manifest

`vendor/app.manifest` is assembled from the `package.appxfragment` files of the
three Windows App SDK components (Foundation, InteractiveExperiences, WinUI).
`vendor/app.rc` embeds it as resource id 1, type 24 (`RT_MANIFEST`), and
`nimble manifest` compiles that to `src/winui3/app.res` with `windres`.
`deploy.nim` then links it with a single `{.passL.}`.

It is *linked*, not copied beside the executable, and that is the single most
important detail here. Windows caches the activation context by executable path
**and timestamp**, including the result when no manifest was found. So an
external `myapp.exe.manifest` that appears after the first run changes nothing
until the binary is rebuilt — and that failure looks exactly like a broken
manifest. A resource cannot be got wrong that way.

## Opting out

```
nim c -d:winui3NoAutoStage myapp.nim
```

Staging is skipped; the manifest is still not linked either, so you are taking
on both halves. `RuntimeFiles` is exported, so a build script can copy the same
set:

```nim
import winui3

for name in RuntimeFiles:
  echo name
```

`ManifestResource` is the path to the compiled resource, if you want to link it
yourself.

## What you ship

A folder: your executable and the DLLs beside it, about 54 MB. Nothing is
installed on the user's machine, there is no bootstrapper, and it runs on any
Windows 10 1809 or later.

Every WinUI 3 app pays this one way or another. The Rust `windows-reactor`
crate advertises a "single ~3 MB binary" and its build script stages 28 DLLs
and 50 MB beside that binary, which is the same arrangement.

### The cost

The SDK travels with your app, so a security fix in it reaches your users when
you rebuild, not before. Letting Windows service the runtime instead means
packaging as MSIX with a framework dependency — real, documented, and not what
this library sets up for you.

## When activation fails anyway

`REGDB_E_CLASSNOTREG` from a WinUI class has exactly two causes, and the
library's error message names both along with the paths it checked:

- **The SDK is not beside the executable.** Usually because the build could not
  find an installed runtime to stage from — the compiler said so at the time.
- **The manifest is not in the executable.** Rebuild. And remember the
  timestamp caching: if a stale `myapp.exe.manifest` is sitting beside the
  binary it takes precedence over the embedded one, so delete it.

## In CI

A fresh GitHub Actions `windows-latest` runner has no Windows App SDK, so
nothing to stage from. Installing it is a download and a silent run:

```yaml
- run: |
    curl -L -o wasdk.exe https://aka.ms/windowsappsdk/1.7/latest/windowsappruntimeinstall-x64.exe
    ./wasdk.exe --quiet
```

The workflow in `.github/workflows/ci.yml` does this. Without it, builds still
succeed — they just print the "not staged" notice and produce executables that
cannot start.
