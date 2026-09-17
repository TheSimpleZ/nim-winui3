version       = "1.6.0"
author        = "Zrean Tofiq"
description   = "WinUI 3 desktop applications in Nim, via the WinRT ABI"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.0"
requires "winrt >= 0.1.0"

task test, "Run the end-to-end UI tests on an isolated desktop":
  exec "powershell -ExecutionPolicy Bypass -File tests/run.ps1"

task bindings, "Regenerate both generated layers from the winmd":
  ## The generators live in the winrt package, because what they do is project
  ## WinRT metadata and nothing about them is specific to XAML. The extra
  ## arguments say where the generated code finds the runtime (`winrt/core`)
  ## and which module already declares the `Windows.*` types this metadata
  ## refers to but does not define (`winrt/foundation`).
  ##
  ## The result is checked in, so this is a maintainer's task, not a build
  ## step, and it expects the winrt repository checked out beside this one.
  const winrt = "../winrt-nim"
  exec "nim c -d:release --hints:off -o:bin/generate.exe " & winrt & "/tools/generate.nim"
  exec "nim c -d:release --hints:off -o:bin/wrappers.exe " & winrt & "/tools/wrappers.nim"
  exec "./bin/generate.exe vendor/Microsoft.UI.Xaml.winmd Microsoft.UI.Xaml " &
       "src/winui3/generated/xaml_abi.nim winrt/core winrt/foundation"
  exec "./bin/wrappers.exe vendor/Microsoft.UI.Xaml.winmd Microsoft.UI.Xaml " &
       "src/winui3/generated/xaml_api.nim winrt/core"

task manifest, "Rebuild vendor/app.res from vendor/app.manifest":
  ## An embedded RT_MANIFEST is what lets an app activate WinUI classes without
  ## an external .exe.manifest, which has to be in place before the first run
  ## or Windows caches the failure.
  exec "windres -I vendor -O coff vendor/app.rc -o vendor/app.res"
