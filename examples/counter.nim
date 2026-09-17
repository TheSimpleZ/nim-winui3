## An interactive WinUI 3 app: a button that changes a label.
##
## Exercises the parts a real GUI needs — a panel with several children, a
## composable control, and an event handler calling back into Nim.
##
## ```
## nim c -r --path:src --outdir:bin examples/counter.nim
## ```

import std/strformat
import winui3

start proc() =
  let window = newWindow()
  window.title = "Counter"
  window.backdrop = mica

  let panel = newStackPanel(Orientation_Vertical, spacing = 16.0)
  panel.margin = Thickness(left: 40.0, top: 32.0, right: 40.0, bottom: 32.0)

  let label = newTextBlock("Clicked 0 times")
  label.fontSize = 28.0

  var count = 0
  let button = newButton("Click me")
  # The closure captures `count` and `label`; the delegate keeps it alive in a
  # module-level table so the GC cannot collect the environment out from under
  # WinUI.
  button.onClick proc() =
    count.inc
    label.text = &"Clicked {count} " & (if count == 1: "time" else: "times")

  panel.add label, button

  window.content = panel
  window.activate()
