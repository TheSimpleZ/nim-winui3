## What Windows says this process is using.
##
## Three different counters, because they catch different mistakes:
##
## * **private bytes** — a missed `Release`, or a Nim closure never collected.
## * **kernel handles** — an event, a file or a thread handle left open.
## * **GDI and USER objects** — the classic Win32 leak. These have a hard
##   per-process ceiling of 10,000, so leaking them kills an app that a memory
##   leak would only slow down.
##
## Used by `tsoak` to assert and by `tleakhunt` to measure.

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

  Usage* = object
    privateBytes*: int
    handles*: int
    gdi*: int
    user*: int

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

proc privateBytes*(): int =
  ## Private commit, in bytes — the counter a leak moves.
  var mem = ProcessMemoryCounters(cb: uint32(sizeof(ProcessMemoryCounters)))
  discard getProcessMemoryInfo(getCurrentProcess(), mem.addr, mem.cb)
  int(mem.privateUsage)

proc sample*(): Usage =
  ## All four counters, read at one moment.
  let me = getCurrentProcess()
  var handles: uint32
  discard getProcessHandleCount(me, handles.addr)
  Usage(privateBytes: privateBytes(),
        handles: int(handles),
        gdi: int(getGuiResources(me, GR_GDIOBJECTS)),
        user: int(getGuiResources(me, GR_USEROBJECTS)))

proc `$`*(u: Usage): string =
  $(u.privateBytes div 1024) & " KiB, " & $u.handles & " handles, " &
  $u.gdi & " GDI, " & $u.user & " USER"
