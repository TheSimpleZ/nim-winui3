## End-to-end tests against a live WinUI 3 application, through the one
## public import.
##
## This proves that an app written the way the README shows one actually works:
## the WinRT apartment, registration-free activation, an aggregated
## `Application`, the Fluent theme, layout, and a Nim event handler invoked by
## XAML itself.
##
## Two things make that testable without a person watching.
##
## **Assertions come from the layout engine, not from pixels.** A composited
## window captures as a black rectangle whenever the display is asleep, which
## is indistinguishable from a control that never rendered. `actualSize` is
## true whatever the display is doing.
##
## **Clicks go through UI Automation.** Synthetic mouse input cannot reach a
## window on a non-active Windows desktop, and switching desktops to reach it
## would take over the screen. `invoke` raises the same `Click` the mouse
## would.
##
## Run it with `tests/run.ps1`, which builds beside the SDK runtime and
## launches it on its own desktop.

import std/exitprocs
import ../src/winui3

var failures = 0
var checks = 0

proc check(name: string, ok: bool, detail = "") =
  checks.inc
  if ok:
    echo "  ok    " & name & (if detail.len > 0: "  (" & detail & ")" else: "")
  else:
    failures.inc
    echo "  FAIL  " & name & (if detail.len > 0: "  (" & detail & ")" else: "")
  flushFile(stdout)

proc approx(a, b: float64, tolerance = 0.5): bool =
  abs(a - b) <= tolerance

when isMainModule:
  setProgramResult(1)   # until the run completes, treat it as a failure
  start(proc() =
    let window = newWindow()
    window.title = "winui3 tests"
    window.backdrop = mica

    let panel = newStackPanel(Orientation_Vertical, spacing = 16.0)
    let label = newTextBlock("Clicked 0 times")
    label.fontSize = 28.0

    var count = 0
    let button = newButton("Click me")
    button.onClick proc() =
      count.inc
      label.text = "Clicked " & $count & (if count == 1: " time" else: " times")

    panel.add label, button
    window.content = panel

    check("Application.Current exists", not application().isNil)
    check("start reports itself as running", isRunning())
    check("theme merged into Application.Resources",
          mergedDictionaryCount(application()) >= 1,
          "dictionaries: " & $mergedDictionaryCount(application()))
    check("TextBlock.Text round-trips", label.text == "Clicked 0 times",
          label.text)

    panel.onLoaded proc() =
      try:
        let p = panel.actualSize
        let l = label.actualSize
        let b = button.actualSize

        check("panel filled the window", p.width > 100 and p.height > 100,
              $p.width & " x " & $p.height)
        check("TextBlock measured", l.width > 0 and l.height > 0,
              $l.width & " x " & $l.height)
        # A Button with no Fluent template collapses to nothing; the themed
        # default is 32 effective pixels tall.
        check("Button has the Fluent template", approx(b.height, 32.0),
              "height " & $b.height)
        check("stacked vertically, not side by side",
              p.height >= l.height + b.height,
              $p.height & " >= " & $l.height & " + " & $b.height)

        button.invoke()
        check("Click handler ran", count == 1, "count " & $count)
        check("handler updated the tree", label.text == "Clicked 1 time",
              label.text)

        button.invoke()
        button.invoke()
        check("handler is still wired after repeats", count == 3,
              "count " & $count)
        check("plural text", label.text == "Clicked 3 times", label.text)

        # A process hosts one XAML application; a second message loop would
        # deadlock rather than fail cleanly, so `start` refuses outright.
        var refused = false
        try:
          start(proc() = discard)
        except WinRtError:
          refused = true
        check("a second start() is refused", refused)
      except CatchableError as e:
        check("no exception during layout checks", false, e.msg)

      echo ""
      echo (if failures == 0: "PASS" else: "FAIL") &
           ": " & $(checks - failures) & "/" & $checks & " checks"
      flushFile(stdout)
      setProgramResult(if failures == 0: 0 else: 1)
      exitApp()

    window.activate()
  )
