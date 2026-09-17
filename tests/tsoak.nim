## A soak test: does the library survive being used for a long time?
##
## The intended application for this library is a tray utility that runs for
## days, so the failure that matters is not a crash on startup but a slow
## climb. `tlifetime` proves individual reference counts balance; this runs a
## realistic UI workload tens of thousands of times and watches what the
## operating system says about the process.
##
## Three counters, because they catch different mistakes:
##
## * **private bytes** — a missed `Release`, or a Nim closure never collected.
## * **kernel handles** — an event, a file or a thread handle left open.
## * **GDI and USER objects** — the classic Win32 leak. These have a hard
##   per-process ceiling of 10,000, so leaking them kills an app that a memory
##   leak would only slow down.
##
## A single sample proves nothing: allocators keep freed pages, and the first
## use of a control type loads resources that are never released by design. So
## this measures three equal phases and compares them — a leak is *linear*,
## while a one-off cost flattens.
##
## The workload deliberately does not call `invoke`. That is the UI Automation
## path, and `IInvokeProvider.Invoke` allocates inside XAML on every call —
## about 157 bytes, measured in `tleakhunt`, with this library's own peer
## lookup and pattern query at exactly zero. A user pressing a button does not
## go through it, so including it here would measure WinUI rather than this
## library, and would hide a real regression behind a constant.

import std/exitprocs
import ../src/winui3

# --- what Windows says about this process ---------------------------------

type
  ProcessMemoryCounters {.pure.} = object
    cb: uint32
    pageFaultCount: uint32
    peakWorkingSetSize: uint
    workingSetSize: uint
    quotaPeakPagedPoolUsage: uint
    quotaPagedPoolUsage: uint
    quotaPeakNonPagedPoolUsage: uint
    quotaNonPagedPoolUsage: uint
    pagefileUsage: uint
    peakPagefileUsage: uint
    privateUsage: uint

proc getCurrentProcess(): pointer
  {.importc: "GetCurrentProcess", dynlib: "kernel32", stdcall.}
proc getProcessMemoryInfo(process: pointer, counters: ptr ProcessMemoryCounters,
                          cb: uint32): int32
  {.importc: "K32GetProcessMemoryInfo", dynlib: "kernel32", stdcall.}
proc getProcessHandleCount(process: pointer, count: ptr uint32): int32
  {.importc: "GetProcessHandleCount", dynlib: "kernel32", stdcall.}
proc getGuiResources(process: pointer, flags: uint32): uint32
  {.importc: "GetGuiResources", dynlib: "user32", stdcall.}

const
  GR_GDIOBJECTS = 0'u32
  GR_USEROBJECTS = 1'u32

type
  Usage = object
    privateBytes: int
    handles: int
    gdi: int
    user: int

proc sample(): Usage =
  let me = getCurrentProcess()
  var mem = ProcessMemoryCounters(cb: uint32(sizeof(ProcessMemoryCounters)))
  discard getProcessMemoryInfo(me, mem.addr, mem.cb)
  var handles: uint32
  discard getProcessHandleCount(me, handles.addr)
  Usage(privateBytes: int(mem.privateUsage),
        handles: int(handles),
        gdi: int(getGuiResources(me, GR_GDIOBJECTS)),
        user: int(getGuiResources(me, GR_USEROBJECTS)))

proc `$`(u: Usage): string =
  $(u.privateBytes div 1024) & " KiB, " & $u.handles & " handles, " &
  $u.gdi & " GDI, " & $u.user & " USER"

# --- the workload ----------------------------------------------------------

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

proc buildAndDiscardUi(host: Panel) =
  ## One round of what an app actually does: build a small subtree, set
  ## properties of every kind, wire an event, fire it, then drop the lot.
  let card = newBorder()
  card.padding = Thickness(left: 8.0, top: 8.0, right: 8.0, bottom: 8.0)
  card.cornerRadius = CornerRadius(topLeft: 4.0, topRight: 4.0,
                                   bottomRight: 4.0, bottomLeft: 4.0)
  let brush = newSolidColorBrush()
  brush.color = Color(a: 255, r: 32, g: 32, b: 32)
  card.background = brush

  let inner = newStackPanel(Orientation_Vertical, spacing = 4.0)
  let label = newTextBlock("soak")
  label.fontSize = 12.0
  discard label.text
  discard label.fontSize

  let button = newButton("go")
  let token = button.onClick(proc() = discard)
  inner.add label, button
  card.child = inner

  host.children.add card
  discard host.children.len
  button.removeClick(token)
  host.children.clear()

when isMainModule:
  setProgramResult(1)
  start(proc() =
    let window = newWindow()
    window.title = "soak"
    let host = newStackPanel(Orientation_Vertical)
    window.content = host
    window.activate()

    const Phase = 20_000

    # Three phases, not two. A single before/after cannot tell a leak from an
    # allocator holding freed pages or a control type caching its template on
    # first use — both look like growth. A leak is *linear*: the second phase
    # costs what the first did. Anything that flattens was a one-off.
    var marks: seq[Usage]
    for phase in 0 .. 2:
      for _ in 1 .. Phase:
        buildAndDiscardUi(host)
      marks.add sample()
      echo "  after " & $((phase + 1) * Phase) & " iterations: " & $marks[^1]
      flushFile(stdout)

    let firstKiB = (marks[1].privateBytes - marks[0].privateBytes) div 1024
    let secondKiB = (marks[2].privateBytes - marks[1].privateBytes) div 1024
    echo "  growth per phase: " & $firstKiB & " KiB then " & $secondKiB & " KiB"
    flushFile(stdout)

    # Steady state is what a long-running app lives in, so the later phase is
    # the one that matters. At 200 bytes an iteration this would be 4 MiB.
    check("steady-state memory is flat over " & $Phase & " iterations",
          secondKiB < 512, $secondKiB & " KiB in the third phase")
    check("growth is not linear in the work done",
          secondKiB <= max(firstKiB, 64),
          $firstKiB & " KiB then " & $secondKiB & " KiB")
    check("kernel handles stable",
          marks[2].handles - marks[0].handles < 50,
          $(marks[2].handles - marks[0].handles) & " more handles")
    check("GDI objects stable",
          marks[2].gdi - marks[0].gdi < 50,
          $(marks[2].gdi - marks[0].gdi) & " more GDI")
    check("USER objects stable",
          marks[2].user - marks[0].user < 50,
          $(marks[2].user - marks[0].user) & " more USER")

    let (slots, free) = delegateTableSizes()
    check("the delegate table did not grow with the workload",
          slots < 64, $slots & " slots, " & $free & " free")

    echo ""
    echo (if failures == 0: "PASS" else: "FAIL") &
         ": " & $(checks - failures) & "/" & $checks & " checks"
    flushFile(stdout)
    setProgramResult(if failures == 0: 0 else: 1)
    exitApp()
  )
