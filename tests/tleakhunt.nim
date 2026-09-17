## Which operation leaks? A bisection harness, not a pass/fail suite.
##
## `tsoak` says a realistic workload grows linearly; that tells you there is a
## leak but not where. This runs each operation on its own, many times, and
## prints bytes-per-iteration for each, so the culprit is whichever line is not
## ~0.
##
## `tests/run.ps1` builds it but does not run it: it has no assertions to
## fail, and its output is numbers to read. Building it keeps it from rotting.
## To use it, build it like any suite and run the executable.

import std/strutils
import winui3
import winui3/generated/xaml_abi
import ./usage

const Reps = 20_000

proc measure(name: string, body: proc()) =
  ## Warm up first so one-off allocations land before the baseline, then
  ## measure the same work again.
  for _ in 1 .. Reps: body()
  let before = privateBytes()
  for _ in 1 .. Reps: body()
  let after = privateBytes()
  let perIter = (after - before) / Reps
  echo "  " & name & ": " &
       $((after - before) div 1024) & " KiB over " & $Reps & "  =  " &
       formatFloat(perIter, ffDecimal, 1) & " bytes/iteration"
  flushFile(stdout)

when isMainModule:
  start(proc() =
    let window = newWindow()
    window.title = "leak hunt"
    let host = newStackPanel(Orientation.Vertical)
    window.content = host
    window.activate()

    let sharedLabel = newTextBlock("shared")
    let sharedButton = newButton("shared")
    let sharedBrush = newSolidColorBrush()
    host.children.add sharedButton

    measure("nothing (baseline noise)", proc() = discard)

    measure("newTextBlock()", proc() =
      let t = newTextBlock()
      discard t.isNil)
    measure("newButton() (composable + caption)", proc() =
      let b = newButton()
      discard b.isNil)
    measure("newSolidColorBrush()", proc() =
      let b = newSolidColorBrush()
      discard b.isNil)
    measure("newBorder()", proc() =
      let b = newBorder()
      discard b.isNil)

    measure("read a string property", proc() =
      discard sharedLabel.text)
    measure("write a string property", proc() =
      sharedLabel.text = "written")
    measure("read a float property", proc() =
      discard sharedLabel.fontSize)
    measure("read a struct property", proc() =
      discard sharedLabel.margin)
    measure("write a struct property", proc() =
      sharedLabel.margin = Thickness(left: 1.0, top: 1.0,
                                     right: 1.0, bottom: 1.0))
    measure("read an interface property", proc() =
      discard host.children)
    measure("read an enum property", proc() =
      discard host.orientation)
    measure("write a brush (class-typed argument)", proc() =
      host.background = sharedBrush)

    measure("children add + clear", proc() =
      host.children.add sharedLabel
      host.children.clear())

    measure("subscribe + unsubscribe", proc() =
      let t = sharedButton.onClick(proc() = discard)
      sharedButton.removeClick(t))

    # With no handler attached, this measures `invoke` itself. With one, it
    # also measures the delegate trampoline and the event arguments — so the
    # difference between the two says which side leaks.
    measure("invoke, no handler attached", proc() =
      sharedButton.invoke())

    var fired = 0
    let token = sharedButton.onClick(proc() = fired.inc)
    measure("invoke, handler attached", proc() =
      sharedButton.invoke())
    sharedButton.removeClick(token)

    measure("borrowed[] wrapper on its own", proc() =
      let args = borrowed[RoutedEventArgs](sharedLabel.p)
      discard args.isNil)

    # Split `invoke` into its three steps. Whichever one grows is the answer,
    # and if it is the last then the allocation is XAML's rather than ours —
    # which matters, because `invoke` exists for tests and automation, not for
    # the path a user's click actually takes.
    measure("  step 1: peer lookup only", proc() =
      let p = sharedButton.automationPeer()
      release(p))

    measure("  step 2: peer + GetPattern", proc() =
      let p = sharedButton.automationPeer()
      let ap = queryInterface(p, IID_IAutomationPeer)
      release(p)
      var pattern: pointer
      discard vcall(ap, Slot_IAutomationPeer_GetPattern,
                    proc(self: pointer, a1: int32,
                         value: ptr pointer): HRESULT {.stdcall.})(
                      ap, int32(PatternInterface.Invoke), pattern.addr)
      release(ap)
      release(pattern))

    measure("  step 3: the whole thing (adds IInvokeProvider.Invoke)", proc() =
      sharedButton.invoke())

    echo ""
    echo "done"
    flushFile(stdout)
    exitApp()
  )
