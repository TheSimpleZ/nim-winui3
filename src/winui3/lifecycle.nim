## Starting a WinUI 3 application, and the Fluent theme.
##
## Everything else in this library describes objects. This module is the part
## that only happens once: initialise the apartment, construct an aggregated
## `Application`, merge the theme, run the message loop, and stop.
##
## ## Threading
##
## XAML objects may only be created on the UI thread, inside the callback given
## to `start`. Constructing one earlier fails with `RPC_E_WRONG_THREAD`, and
## touching one from another thread afterwards fails the same way.

import winrt/core
import winrt/delegate
import ./app
import ./generated/xaml_abi

# Two signatures the generator leaves unmapped because they involve
# `IVector<T>`, a parameterised generic. The *pointer* shapes are still
# knowable: an interface is a pointer however it was declared.
type
  FnGetPtr = proc(self: pointer, value: ptr pointer): HRESULT {.stdcall.}
  FnAppendPtr = proc(self: pointer, value: pointer): HRESULT {.stdcall.}

# `Windows.Foundation.Collections.IVector<T>` numbers its slots the same way
# whatever `T` is. The IID of a generic instantiation is computed rather than
# declared, but a pointer obtained from `get_MergedDictionaries` already *is*
# that interface, so the slot is all that is needed. `collections.nim` says
# more about why these are hand-written.
const
  SlotVectorSize = 7
  SlotVectorAppend = 13

proc mergedDictionaryCount*(app: pointer): int =
  ## How many dictionaries are merged into `Application.Resources`.
  ##
  ## Negative values report where the walk stopped rather than raising, because
  ## this exists to diagnose a theme that did not take.
  let iapp = queryInterface(app, IID_IApplication)
  if iapp.isNil: return -1
  var resources: pointer
  discard vcall(iapp, Slot_IApplication_get_Resources,
                Fn_IApplication_get_Resources)(iapp, resources.addr)
  release(iapp)
  if resources.isNil: return -2
  let idict = queryInterface(resources, IID_IResourceDictionary)
  release(resources)
  if idict.isNil: return -3
  var merged: pointer
  discard vcall(idict, Slot_IResourceDictionary_get_MergedDictionaries,
                FnGetPtr)(idict, merged.addr)
  release(idict)
  if merged.isNil: return -4
  var n: uint32
  discard vcall(merged, SlotVectorSize,
                proc(self: pointer, v: ptr uint32): HRESULT {.stdcall.})(
                  merged, n.addr)
  release(merged)
  int(n)

proc installControlsResources*(app: pointer) =
  ## Merge `XamlControlsResources` into the application's resources.
  ##
  ## This is what gives every templated control its Fluent style. Without it a
  ## `Button` has no control template and renders as nothing at all, while a
  ## `TextBlock` looks fine because it draws itself — so the symptom reads as a
  ## layout bug rather than a missing theme.
  ##
  ## Two preconditions, both in `app.nim`: the `Application` must be built by
  ## aggregation, and it must expose `IXamlMetadataProvider`. Miss either and
  ## this fails — `E_UNEXPECTED` from `get_Resources` for the first, `E_FAIL`
  ## activating the dictionary for the second.
  let iapp = queryInterface(app, IID_IApplication)
  if iapp.isNil:
    raise newException(WinRtError, "winui3: not an Application")

  var resources: pointer
  try:
    vcall(iapp, Slot_IApplication_get_Resources,
          Fn_IApplication_get_Resources)(iapp, resources.addr)
      .check("Application.Resources")
  finally:
    release(iapp)
  if resources.isNil:
    raise newException(WinRtError, "winui3: Application.Resources is empty")

  try:
    let idict = queryInterface(resources, IID_IResourceDictionary)
    if idict.isNil:
      raise newException(WinRtError, "winui3: Resources is not a dictionary")
    try:
      var merged: pointer
      vcall(idict, Slot_IResourceDictionary_get_MergedDictionaries,
            FnGetPtr)(idict, merged.addr).check("MergedDictionaries")
      if merged.isNil:
        raise newException(WinRtError, "winui3: MergedDictionaries is empty")
      try:
        # Activated, then narrowed to ResourceDictionary — the collection holds
        # dictionaries, not the concrete type.
        let controls = activateInstance(
          "Microsoft.UI.Xaml.Controls.XamlControlsResources")
        try:
          let dict = queryInterface(controls, IID_IResourceDictionary)
          if dict.isNil:
            raise newException(WinRtError,
              "winui3: XamlControlsResources is not a ResourceDictionary")
          try:
            vcall(merged, SlotVectorAppend, FnAppendPtr)(merged, dict)
              .check("MergedDictionaries.Append")
          finally:
            release(dict)
        finally:
          release(controls)
      finally:
        release(merged)
    finally:
      release(idict)
  finally:
    release(resources)

# --------------------------------------------------------------- Application

var
  theApp: pointer = nil
  running = false

proc application*(): pointer =
  ## The aggregated `Application`, or nil before `start` has run.
  theApp

proc isRunning*(): bool =
  ## Whether `start` is currently inside its message loop.
  running

proc exitApp*() =
  ## Ask the application to shut down, ending the message loop in `start`.
  if theApp.isNil:
    return
  let app = queryInterface(theApp, IID_IApplication)
  if app.isNil:
    return
  try:
    vcall(app, Slot_IApplication_Exit,
          proc(self: pointer): HRESULT {.stdcall.})(app).check("Application.Exit")
  finally:
    release(app)

proc start*(onStarted: proc()) =
  ## Start the XAML application and run its message loop.
  ##
  ## Blocks until the application exits. `onStarted` runs on the UI thread and
  ## is the only place XAML objects may be created.
  ##
  ## The apartment is initialised here rather than left to the caller, because
  ## getting it wrong surfaces as `RPC_E_CHANGED_MODE` somewhere far from the
  ## cause.
  if running:
    raise newException(WinRtError,
      "winui3: start() is already running. A process hosts one XAML " &
      "application and one UI thread; call it once, from main.")
  running = true

  let hr = initApartment(singleThreaded)
  if hr == RPC_E_CHANGED_MODE:
    running = false
    raise newException(WinRtError,
      "winui3: this thread is already in a multi-threaded apartment. XAML " &
      "requires a single-threaded one, so call start() from a thread that " &
      "has not initialised COM, or from main.")

  let statics = activationFactory("Microsoft.UI.Xaml.Application",
                                  IID_IApplicationStatics)
  # Two nested callbacks, and the nesting matters. The initialization callback
  # only *constructs* the Application; WinUI then calls `OnLaunched` once it is
  # actually running. Resources merged before that point do not take effect —
  # the dictionary is not live yet — so both the theme and the caller's UI
  # belong in `OnLaunched`.
  let cb = newDelegate(IID_ApplicationInitializationCallback,
                       proc(args: pointer) =
                         theApp = createApplication(onLaunched = proc() =
                           try:
                             installControlsResources(theApp)
                           except CatchableError as e:
                             stderr.writeLine "winui3: theme not applied (" &
                               e.msg & ")"
                           onStarted()))
  try:
    vcall(statics, Slot_IApplicationStatics_Start,
          Fn_IApplicationStatics_Start)(statics, cb).check("Application.Start")
  finally:
    running = false
    release(cb)
    release(statics)
    # Past this point XAML is gone, so wrappers still held by closures must
    # not release into it. See `releaseIfLive`.
    endRuntime()
