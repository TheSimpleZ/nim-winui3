## Lifetime tests: reference counting, and the tables behind delegates.
##
## This is the suite that decides whether the library survives a long-running
## app rather than a demo. WinRT is COM, so a getter hands back a reference the
## caller must release, and there are hundreds of such getters — a GUI that
## leaks one per property read grows without bound.
##
## Nothing here guesses from process memory, which is far too noisy to prove
## anything. `AddRef` and `Release` both return the resulting count, so
## `liveRefs` reads an object's real refcount and the checks are exact.

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

proc liveRefs(p: pointer): int =
  ## The object's current reference count.
  ##
  ## `Release` returns the count *after* the decrement, so an AddRef/Release
  ## pair leaves the object exactly as it was and reports what it already had.
  if p.isNil: return 0
  addRef(p)
  int(release(p))

const Iterations = 20_000

when isMainModule:
  setProgramResult(1)
  start(proc() =
    let window = newWindow()
    window.title = "lifetime tests"
    let panel = newStackPanel()

    # ---- a getter that returns an interface ----------------------------
    #
    # `Panel.Children` hands back the same collection every time, with the
    # count bumped. Without a destructor this grows by one per read.
    block:
      let children = panel.children
      let before = liveRefs(children.p)
      check("baseline refcount is sane", before > 0, $before)

      for _ in 1 .. Iterations:
        discard panel.children.len

      let after = liveRefs(children.p)
      check("reading a property " & $Iterations & " times leaks nothing",
            after == before, $before & " -> " & $after)

    # ---- copies and moves ----------------------------------------------
    #
    # A plain `let a = b` is not necessarily a copy: Nim's ORC turns a binding
    # that cannot outlive its source into a cursor, which borrows rather than
    # counts. That is correct and costs nothing, so what matters is the case
    # where a reference really does have to be kept — stored somewhere that
    # outlives the original.
    block:
      let children = panel.children
      let before = liveRefs(children.p)
      var kept: UIElementCollection
      block inner:
        kept = panel.children     # a real copy into a longer-lived var
        check("a stored reference is counted",
              liveRefs(children.p) == before + 1, $liveRefs(children.p))
      check("still held after the block that made it",
            liveRefs(children.p) == before + 1, $liveRefs(children.p))
      kept = UIElementCollection()      # overwrite: the old one is released
      check("overwriting a reference releases the old one",
            liveRefs(children.p) == before, $liveRefs(children.p))

    # ---- storing wrappers in a seq -------------------------------------
    block:
      let children = panel.children
      let before = liveRefs(children.p)
      block inner:
        var kept: seq[UIElementCollection]
        for _ in 1 .. 100:
          kept.add panel.children
        check("100 stored references are all counted",
              liveRefs(children.p) == before + 100, $liveRefs(children.p))
      check("the seq released them all",
            liveRefs(children.p) == before, $liveRefs(children.p))

    # ---- elements added to the tree ------------------------------------
    #
    # `UIElementCollection.Append` does *not* AddRef the element — XAML owns
    # tree children through its own peer system rather than through COM. So the
    # question is not what the count says but whether an element stays usable
    # once every Nim reference to it is gone, which is the case that would
    # otherwise be a use-after-free in every app built on this.
    block:
      var raw: pointer
      block inner:
        let label = newTextBlock()
        label.text = "parented, then abandoned"
        raw = label.p
        panel.add label
      # Every Nim reference to the label has now been destroyed.
      let fromTree = panel.children[0]
      let tb = queryInterface(fromTree.p, IID_ITextBlock)
      check("an abandoned child is still in the tree", not tb.isNil)
      if not tb.isNil:
        let text = TextBlock(p: tb).text
        check("its text survives the last reference going away",
              text == "parented, then abandoned", text)

    # ---- event arguments are lent, not given ----------------------------
    #
    # A handler's `args` belongs to XAML. Adopting it without an AddRef would
    # over-release and free an object still in use — which shows up as a crash
    # somewhere else entirely, so this runs enough times to be sure.
    block:
      let button = newButton()
      panel.add button
      var fired = 0
      let token = button.onClick(proc(sender: pointer, args: RoutedEventArgs) =
        fired.inc
        # Touch the arguments, and copy them, so an over-release would bite.
        let copy = args
        if copy.isNil: fired.dec)
      for _ in 1 .. 2_000:
        button.invoke()
      check("2000 events, arguments never over-released", fired == 2_000,
            $fired)
      button.removeClick(token)

    # ---- delegate tables reuse their slots ------------------------------
    block:
      let button = newButton()
      panel.add button
      # Prime the tables, then measure: the first few subscriptions may grow
      # them legitimately.
      for _ in 1 .. 50:
        let t = button.onClick(proc(sender: pointer, args: RoutedEventArgs) = discard)
        button.removeClick(t)
      let (slotsBefore, _) = delegateTableSizes()
      for _ in 1 .. 5_000:
        let t = button.onClick(proc(sender: pointer, args: RoutedEventArgs) = discard)
        button.removeClick(t)
      let (slotsAfter, freeAfter) = delegateTableSizes()
      check("5000 subscribe/unsubscribe cycles reuse delegate slots",
            slotsAfter == slotsBefore,
            $slotsBefore & " -> " & $slotsAfter & ", " & $freeAfter & " free")

    # ---- creating and dropping whole controls ---------------------------
    #
    # Nothing to compare a count against here, since each control is new; this
    # is checking that construction and destruction survive being repeated.
    block:
      for _ in 1 .. Iterations:
        let t = newTextBlock()
        t.text = "churn"
        discard t.text
      check("creating " & $Iterations & " controls did not fault", true)

    window.content = panel
    window.activate()

    echo ""
    echo (if failures == 0: "PASS" else: "FAIL") &
         ": " & $(checks - failures) & "/" & $checks & " checks"
    flushFile(stdout)
    setProgramResult(if failures == 0: 0 else: 1)
    exitApp()
  )
