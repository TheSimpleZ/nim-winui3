## The smallest complete WinUI 3 application.
##
## Build and run it from the repository root:
##
## ```
## nim c -r --path:src --outdir:bin examples/hello.nim
## ```
##
## Nothing else to set up: importing `winui3` stages the Windows App SDK into
## the output directory and links the manifest into the executable.

import winui3

start proc() =
  let window = newWindow()
  window.title = "Hello from Nim"
  # Mica: the material Windows 11's own Settings app uses.
  window.backdrop = mica

  let heading = newTextBlock("WinUI 3, from Nim")
  heading.fontSize = 32.0
  heading.margin = Thickness(left: 40.0, top: 32.0, right: 40.0, bottom: 32.0)

  window.content = heading
  window.activate()
