## What happens when things go wrong.
##
## A library is production-ready when misuse produces a diagnosis rather than a
## crash, and when a mistake in *user* code cannot take the process down. Two
## rules matter most here:
##
## * A Nim exception must never unwind into WinUI. C++ is on the other side of
##   the ABI and the behaviour is undefined, so every callback catches and
##   converts to an HRESULT. If that ever stops working, the process dies
##   inside XAML with no stack worth reading.
##
## * A nil or wrong-typed object must raise something that names the problem.
##   The failure mode to avoid is a null dereference, which on this path means
##   calling through a vtable at address zero.

import std/strutils
import winui3
import ./checks

proc raises(body: proc()): string =
  ## The message, or "" if nothing was raised. A crash is not a return value,
  ## so reaching the next line at all is part of what is being tested.
  try:
    body()
    ""
  except CatchableError as e:
    if e.msg.len > 0: e.msg else: "<empty message>"

when isMainModule:
  beginSuite()
  start(proc() =
    let window = newWindow()
    window.title = "error tests"
    let panel = newStackPanel(Orientation.Vertical)
    window.content = panel
    window.activate()

    # ---- nil objects --------------------------------------------------
    block:
      let empty = TextBlock()           # never constructed, `p` is nil
      check("a default-constructed object reports itself nil", empty.isNil)

      let readMsg = raises(proc() = discard empty.text)
      check("reading a property of a nil object raises", readMsg.len > 0,
            readMsg)
      check("and the message names the interface, not just a code",
            "ITextBlock" in readMsg, readMsg)

      let writeMsg = raises(proc() = empty.text = "x")
      check("writing a property of a nil object raises", writeMsg.len > 0,
            writeMsg)

      let invokeMsg = raises(proc() = UIElement().invoke())
      check("invoking a nil element raises", invokeMsg.len > 0, invokeMsg)

      check("a nil collection has no length", UIElementCollection().len == 0)

    # ---- wrong type ----------------------------------------------------
    block:
      # A TextBlock is a UIElement but not a Panel, so asking it for Panel
      # behaviour must be refused rather than dispatched through the wrong
      # vtable — which would not be an error, it would be a crash.
      let label = newTextBlock("not a panel")
      # `borrowed`, not `Panel(p: ...)`: the raw form adopts the reference, so
      # the temporary would release one this scope never took and corrupt the
      # heap at exit. That is the whole reason `owned` and `borrowed` exist.
      let msg = raises(proc() = discard borrowed[Panel](label.p).children)
      check("asking a TextBlock for Panel.Children raises", msg.len > 0, msg)
      check("survived the wrong-interface call", not label.isNil)

    # ---- activation failure ---------------------------------------------
    block:
      let msg = raises(proc() =
        discard activateInstance("Microsoft.UI.Xaml.Controls.NoSuchControl"))
      check("activating a class that does not exist raises", msg.len > 0)
      check("and says the class id it could not find",
            "NoSuchControl" in msg, msg)

    # ---- an exception inside a user event handler -------------------------
    #
    # This is the one that would end the process. The handler raises every
    # time; the library has to swallow it at the ABI boundary and keep going.
    block:
      let button = newButton("boom")
      panel.add button
      var calls = 0
      button.onClick proc() =
        calls.inc
        raise newException(ValueError, "deliberate failure inside a handler")

      for _ in 1 .. 100:
        button.invoke()
      check("a raising handler does not kill the process", calls == 100,
            $calls & " calls survived")

    # ---- an exception inside onLoaded -------------------------------------
    block:
      let late = newTextBlock("late")
      var ran = false
      late.onLoaded proc() =
        ran = true
        raise newException(ValueError, "deliberate failure inside onLoaded")
      panel.add late
      check("attaching a raising Loaded handler did not fault", not late.isNil)

    # ---- misuse of tokens --------------------------------------------------
    block:
      let button = newButton("tokens")
      panel.add button
      let token = button.onClick(proc() = discard)
      button.removeClick(token)
      # Removing twice is a user error, not a reason to crash.
      let msg = raises(proc() = button.removeClick(token))
      check("removing a handler twice does not crash",
            true, (if msg.len > 0: "raised: " & msg else: "returned quietly"))

      let never = EventRegistrationToken(value: 0)
      let msg2 = raises(proc() = button.removeClick(never))
      check("removing a token that was never issued does not crash",
            true, (if msg2.len > 0: "raised: " & msg2 else: "returned quietly"))

    # ---- still working afterwards -----------------------------------------
    block:
      let label = newTextBlock("still here")
      panel.add label
      check("the application still works after all of that",
            label.text == "still here", label.text)
      check("and the window is still visible", window.visible)

    finishSuite()
  )
