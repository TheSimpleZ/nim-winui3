# How the tests work

```
nimble test
```

Seven suites, 78 checks, a few minutes. Each one builds a real WinUI 3
application, runs it, and exits by itself.

## The suites

| suite | what it holds down |
|---|---|
| `tui` | an app as the README writes one: theme, layout, events, automation |
| `tgenerated` | the generated layer: constructors, properties, enums, inheritance |
| `tstructs` | every by-value struct, round-tripped — a layout mismatch here is silent |
| `tlifetime` | reference counts, measured exactly, and delegate slot reuse |
| `tgenerics` | computed IIDs, against a live object, with a negative control |
| `terrors` | nil objects, wrong interfaces, and exceptions thrown in user callbacks |
| `tsoak` | 60,000 build-and-teardown cycles against private bytes, handles, GDI and USER |

Two supporting modules: `tests/checks.nim` is the shared `check` /
`finishSuite` scaffolding, and `tests/usage.nim` reads what Windows says this
process is using.

`tests/tleakhunt.nim` is not one of the seven. It is a measuring instrument
that prints bytes-per-iteration for each operation on its own, which is how you
find *which* call leaks once `tsoak` says something does. `run.ps1` builds it
so it cannot rot, and does not run it, because it asserts nothing.

## The runner

`tests/run.ps1` builds each suite and launches it on a **Windows desktop of its
own** — `CreateDesktopW` plus `CreateProcessW` with `STARTUPINFO.lpDesktop` —
so the windows never appear on yours and never take your keyboard. `cmd.exe`
does the output redirection, because the suite's output has to survive the run.

It reports **the process exit code as well as the output**. That is not
belt-and-braces: a suite can print `PASS` and still corrupt the heap on the way
out, and only the exit code catches that. Exit code 259 (`STILL_ACTIVE`) means
the suite never finished within its budget, which is also a failure.

There is no precondition about the Windows App SDK: building a suite stages it,
because importing `winui3` stages it. A clean checkout works.

## Three techniques worth stealing

A GUI test has two problems a console test does not — it steals focus, and it
cannot be checked by looking at pixels. The desktop handles the first. These
three handle the rest.

### Assert on layout, not on pixels

A composited WinUI window captures as a black rectangle whenever the display is
asleep — under a title bar that captures perfectly, because DWM draws that. So
a screenshot cannot tell "the control did not render" from "the monitor is
off".

`actualSize` inside `onLoaded` reports what the layout engine actually did, and
is true whatever the display is doing. A `Button` measuring 32 effective pixels
tall is also proof the Fluent template loaded, since an unstyled one collapses
to nothing — which is how `tui` tells a missing theme from a layout bug.

### Click through UI Automation

Synthetic mouse input cannot reach a window on a desktop that is not the active
input desktop: `SetCursorPos` there silently leaves the cursor at 0,0. And
switching desktops to reach it would take over the screen.

`invoke` goes through XAML's own invoke pattern, so a `Button` raises a real
`Click` and every handler runs. It is not a shortcut around the event system,
it is the event system — and it is how assistive technology drives an
application, so anything reachable this way is reachable by a screen reader.

### Measure three phases, not two

A before-and-after memory reading cannot tell a leak from an allocator holding
freed pages, or from a control type caching its template on first use. Both
look like growth.

A leak is *linear*: the third phase costs what the second did. Anything that
flattens was a one-off. That distinction is what turned "4 MB, probably fine"
into a real missing `WindowsDeleteString`.

`tsoak` deliberately does not call `invoke` in its workload.
`IInvokeProvider.Invoke` allocates about 157 bytes inside XAML on every call
and does not give them back — measured in `tleakhunt`, with this library's own
peer lookup and pattern query at exactly zero. That is WinUI's behaviour on the
automation path, and a user pressing a button does not go through it, so
including it would measure WinUI rather than this library and would hide a real
regression behind a constant.

## Writing a new suite

```nim
import winui3
import ./checks

when isMainModule:
  beginSuite()
  start(proc() =
    let window = newWindow()
    window.title = "my suite"
    window.content = newTextBlock("hello")
    window.activate()

    check("the window is visible", window.visible)

    finishSuite()
  )
```

`beginSuite` sets the exit code to failure up front, so a suite that never
reaches `finishSuite` is a failure rather than a silent success. Add the name
to `$suites` in `tests/run.ps1`.

## In CI

`.github/workflows/ci.yml` installs the Windows App SDK runtime on the runner
and runs the same `nimble test`, plus a type-check and a build of all three
examples. See the comments in that file for what a GitHub runner can and cannot
do with a GUI.
