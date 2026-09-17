## A WinUI 3 window, using only the library's public API.
##
## Build:
##
## ```
## nim c --outdir:bin examples/hello.nim
## ```
##
## Then stage the Windows App SDK DLLs and an `hello.exe.manifest` beside the
## executable — see the README — and run `bin/hello.exe`.

import ../src/winui3

start proc() =
  let window = newWindow()
  window.title = "Hello from Nim"
  # Mica: the material Windows 11's own Settings app uses.
  window.backdrop = mica

  let heading = newTextBlock("WinUI 3, from Nim")
  heading.fontSize = 32.0

  # v0.1 hosts a single element: panel children need UIElementCollection,
  # which is not wrapped yet. See the roadmap.
  window.content = heading

  window.activate()
