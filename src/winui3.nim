## winui3 — WinUI 3 desktop applications in Nim.
##
## ```nim
## import winui3
##
## start proc() =
##   let window = newWindow()
##   window.title = "Hello from Nim"
##   window.backdrop = mica      # the material Windows 11 Settings uses
##
##   let panel = newStackPanel(Orientation.Vertical, spacing = 12.0)
##   let label = newTextBlock("Clicked 0 times")
##
##   var clicks = 0
##   let button = newButton("Click me")
##   button.onClick proc() =
##     clicks.inc
##     label.text = "Clicked " & $clicks & " times"
##
##   panel.add label, button
##   window.content = panel
##   window.activate()
## ```
##
## ## What is in here
##
## Almost all of it is generated from `Microsoft.UI.Xaml.winmd` — 894 classes
## with their properties, methods and events — so if WinUI 3 has something,
## this has it, whether or not the README happens to mention it. The
## hand-written part is the application lifecycle, the aggregated
## `Application`, generic collections, UI Automation, and a handful of
## conveniences.
##
## The WinRT runtime underneath — strings, GUIDs, apartments, activation,
## refcounting, and the COM objects WinUI calls back into — is the separate
## `winrt` package, and this module re-exports it.
##
## ## Lifetimes
##
## Every object is one pointer wide and reference-counted by the compiler:
## `=destroy` releases and `=copy` retains. Reading a property does not leak,
## storing one does not dangle, and nothing needs releasing by hand.
##
## ## Threading
##
## XAML objects may only be created and used on the UI thread, inside the
## callback passed to `start`. Anything else fails with `RPC_E_WRONG_THREAD`.
##
## ## Deployment
##
## Nothing to do. WinUI 3 is not part of Windows, so an app needs the SDK's
## DLLs beside it and a manifest naming the classes they activate — and both
## happen when you build. Importing this module stages the runtime into your
## output directory and links the manifest into your executable.
##
## The output directory ends up around 54 MB, almost all of it Microsoft's.
## `-d:winui3NoAutoStage` turns the staging off if you would rather do it
## yourself; `RuntimeFiles` then names what to copy.

import winui3/deploy
import winrt/core
import winrt/delegate
import winui3/generated/xaml_abi
import winui3/generated/xaml_api
import winui3/collections
import winui3/automation
import winui3/controls
import winui3/app
import winui3/lifecycle

export deploy
export core
export delegate
export xaml_abi
export xaml_api
export collections
export automation
export controls
export app
export lifecycle
