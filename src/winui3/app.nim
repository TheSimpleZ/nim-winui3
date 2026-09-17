## Deriving from `Application` — COM aggregation with two interfaces.
##
## Everything else in this library *calls* WinRT. This subclasses it, which is
## a stricter contract, and it is what makes Fluent styles work at all.
##
## Two things are required together, and neither is enough alone:
##
## **Aggregation.** An `Application` built with a nil outer pointer is only
## half-built and answers `E_UNEXPECTED` from `get_Resources`. The supported
## construction passes our own object as `outer` to
## `IApplicationFactory.CreateInstance`, then forwards every interface we do
## not implement to the `inner` it hands back. This is what
## `winrt::make<App>()` does in C++/WinRT.
##
## **A XAML metadata provider.** `XamlControlsResources` parses `generic.xaml`,
## and parsing XAML means resolving type names. With no `IXamlMetadataProvider`
## on the application there is nothing to resolve them with, and activation
## fails with a bare `E_FAIL` that says nothing about the cause. The work is
## delegated to `XamlControlsXamlMetaDataProvider`, which ships in the SDK and
## knows every built-in control.
##
## ## Laying out two interfaces
##
## A COM object exposing two interfaces cannot serve both from one vtable —
## each interface pointer must point at its *own* table. So the object begins
## with two vtable pointers, and `QueryInterface` hands out the address of
## whichever field matches. The metadata methods then step back from that
## field to find the object.

import std/strformat
import winrt/core
import winrt/delegate
import ./generated/xaml_abi

type
  AppOverridesVtbl {.pure.} = object
    queryInterface: proc(self: pointer, riid: ptr GUID,
                         ppv: ptr pointer): HRESULT {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    getIids: proc(self: pointer, count: ptr uint32,
                  iids: ptr ptr GUID): HRESULT {.stdcall.}
    getRuntimeClassName: proc(self: pointer, name: ptr HSTRING): HRESULT {.stdcall.}
    getTrustLevel: proc(self: pointer, level: ptr int32): HRESULT {.stdcall.}
    onLaunched: proc(self: pointer, args: pointer): HRESULT {.stdcall.}

  XamlMetaVtbl {.pure.} = object
    queryInterface: proc(self: pointer, riid: ptr GUID,
                         ppv: ptr pointer): HRESULT {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    getIids: proc(self: pointer, count: ptr uint32,
                  iids: ptr ptr GUID): HRESULT {.stdcall.}
    getRuntimeClassName: proc(self: pointer, name: ptr HSTRING): HRESULT {.stdcall.}
    getTrustLevel: proc(self: pointer, level: ptr int32): HRESULT {.stdcall.}
    # `TypeName` is a struct larger than a register, so the x64 ABI passes it
    # by address rather than by value.
    getXamlType: proc(self: pointer, typeName: pointer,
                      value: ptr pointer): HRESULT {.stdcall.}
    getXamlTypeByFullName: proc(self: pointer, fullName: HSTRING,
                                value: ptr pointer): HRESULT {.stdcall.}
    getXmlnsDefinitions: proc(self: pointer, count: ptr uint32,
                              value: ptr pointer): HRESULT {.stdcall.}

  AppImpl {.pure.} = object
    ## Field order is the ABI. `appVtbl` at offset 0 makes the object itself a
    ## valid `IApplicationOverrides`; `metaVtbl` is handed out for
    ## `IXamlMetadataProvider`.
    appVtbl: ptr AppOverridesVtbl
    metaVtbl: ptr XamlMetaVtbl
    refs: int32
    inner: pointer      ## the aggregated base Application
    provider: pointer   ## XamlControlsXamlMetaDataProvider, created lazily

const MetaOffset = sizeof(pointer)

proc asImpl(self: pointer): ptr AppImpl {.inline.} =
  cast[ptr AppImpl](self)

proc implFromMeta(self: pointer): ptr AppImpl {.inline.} =
  ## `self` here is the address of `metaVtbl`, one pointer into the object.
  cast[ptr AppImpl](cast[uint](self) - uint(MetaOffset))

var launchHandler: proc() = nil

var metadataCalls* = 0
  ## Diagnostic: how many times XAML asked us to resolve a type.

# ------------------------------------------------------------ IUnknown

proc appAddRef(self: pointer): uint32 {.stdcall.} =
  let a = asImpl(self)
  a.refs.inc
  uint32(a.refs)

proc appRelease(self: pointer): uint32 {.stdcall.} =
  let a = asImpl(self)
  a.refs.dec
  if a.refs <= 0:
    if not a.provider.isNil: discard core.release(a.provider)
    if not a.inner.isNil: discard core.release(a.inner)
    deallocShared(a)
    return 0
  uint32(a.refs)

proc appQueryInterface(self: pointer, riid: ptr GUID,
                       ppv: ptr pointer): HRESULT {.stdcall.} =
  if ppv.isNil:
    return E_POINTER
  let a = asImpl(self)
  if riid[] == IID_IUnknown or riid[] == IID_IApplicationOverrides:
    ppv[] = self
    discard appAddRef(self)
    return S_OK
  if riid[] == IID_IXamlMetadataProvider:
    # A different interface means a different vtable pointer.
    ppv[] = cast[pointer](cast[uint](self) + uint(MetaOffset))
    discard appAddRef(self)
    return S_OK
  # Everything else belongs to the aggregated base.
  if not a.inner.isNil:
    let inner = cast[ptr IInspectable](a.inner)
    return inner.vtbl.queryInterface(a.inner, riid, ppv)
  ppv[] = nil
  E_NOINTERFACE

# Forwarders for the metadata vtable, which receives the inner field address.
proc metaAddRef(self: pointer): uint32 {.stdcall.} =
  appAddRef(cast[pointer](implFromMeta(self)))
proc metaRelease(self: pointer): uint32 {.stdcall.} =
  appRelease(cast[pointer](implFromMeta(self)))
proc metaQueryInterface(self: pointer, riid: ptr GUID,
                        ppv: ptr pointer): HRESULT {.stdcall.} =
  appQueryInterface(cast[pointer](implFromMeta(self)), riid, ppv)

# --------------------------------------------------------- IInspectable

proc appGetIids(self: pointer, count: ptr uint32,
                iids: ptr ptr GUID): HRESULT {.stdcall.} =
  if not count.isNil: count[] = 0
  if not iids.isNil: iids[] = nil
  S_OK

proc appGetRuntimeClassName(self: pointer, name: ptr HSTRING): HRESULT {.stdcall.} =
  if name.isNil: return E_POINTER
  name[] = "Microsoft.UI.Xaml.Application".toHString
  S_OK

proc appGetTrustLevel(self: pointer, level: ptr int32): HRESULT {.stdcall.} =
  if not level.isNil: level[] = 0
  S_OK

# --------------------------------------------------- IApplicationOverrides

proc appOnLaunched(self: pointer, args: pointer): HRESULT {.stdcall.} =
  ## Exceptions are contained here for the same reason as in `delegate`:
  ## unwinding into WinUI's C++ is undefined behaviour.
  if launchHandler.isNil:
    return S_OK
  try:
    launchHandler()
    S_OK
  except CatchableError as e:
    stderr.writeLine &"winui3: OnLaunched raised: {e.msg}"
    E_FAIL

# --------------------------------------------------- IXamlMetadataProvider

proc providerOf(a: ptr AppImpl): pointer =
  ## The SDK's own provider, created on first use and kept for the object's
  ## life. It knows every built-in XAML type, which is exactly what parsing
  ## `generic.xaml` needs.
  if a.provider.isNil:
    let obj = activateInstance(
      "Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider")
    a.provider = queryInterface(obj, IID_IXamlMetadataProvider)
    core.release(obj)
  a.provider

proc metaGetXamlType(self: pointer, typeName: pointer,
                     value: ptr pointer): HRESULT {.stdcall.} =
  let a = implFromMeta(self)
  metadataCalls.inc
  try:
    let p = providerOf(a)
    if p.isNil: return E_FAIL
    vcall(p, Slot_IXamlMetadataProvider_GetXamlType,
             typeof(metaGetXamlType))(p, typeName, value)
  except CatchableError:
    E_FAIL

proc metaGetXamlTypeByFullName(self: pointer, fullName: HSTRING,
                               value: ptr pointer): HRESULT {.stdcall.} =
  let a = implFromMeta(self)
  metadataCalls.inc
  try:
    let p = providerOf(a)
    if p.isNil: return E_FAIL
    vcall(p, Slot_IXamlMetadataProvider_GetXamlType2,
             typeof(metaGetXamlTypeByFullName))(p, fullName, value)
  except CatchableError:
    E_FAIL

proc metaGetXmlnsDefinitions(self: pointer, count: ptr uint32,
                             value: ptr pointer): HRESULT {.stdcall.} =
  let a = implFromMeta(self)
  metadataCalls.inc
  try:
    let p = providerOf(a)
    if p.isNil: return E_FAIL
    vcall(p, Slot_IXamlMetadataProvider_GetXmlnsDefinitions,
             typeof(metaGetXmlnsDefinitions))(p, count, value)
  except CatchableError:
    E_FAIL

var appVtbl = AppOverridesVtbl(
  queryInterface: appQueryInterface,
  addRef: appAddRef,
  release: appRelease,
  getIids: appGetIids,
  getRuntimeClassName: appGetRuntimeClassName,
  getTrustLevel: appGetTrustLevel,
  onLaunched: appOnLaunched)

var metaVtbl = XamlMetaVtbl(
  queryInterface: metaQueryInterface,
  addRef: metaAddRef,
  release: metaRelease,
  getIids: appGetIids,
  getRuntimeClassName: appGetRuntimeClassName,
  getTrustLevel: appGetTrustLevel,
  getXamlType: metaGetXamlType,
  getXamlTypeByFullName: metaGetXamlTypeByFullName,
  getXmlnsDefinitions: metaGetXmlnsDefinitions)

type
  FnAggregateCreate = proc(self: pointer, outer: pointer, inner: ptr pointer,
                           value: ptr pointer): HRESULT {.stdcall.}

proc createApplication*(onLaunched: proc() = nil): pointer =
  ## Construct an aggregated `Application` and return our outer object.
  ##
  ## Must run on the UI thread inside `Application.Start`. Creating it is what
  ## populates `Application.Current`.
  launchHandler = onLaunched

  let outer = cast[ptr AppImpl](allocShared0(sizeof(AppImpl)))
  outer.appVtbl = appVtbl.addr
  outer.metaVtbl = metaVtbl.addr
  outer.refs = 1

  let factory = activationFactory("Microsoft.UI.Xaml.Application",
                                  IID_IApplicationFactory)
  var inner, instance: pointer
  try:
    vcall(factory, Slot_IApplicationFactory_CreateInstance,
             FnAggregateCreate)(factory, cast[pointer](outer), inner.addr,
                                instance.addr)
      .check("Application.CreateInstance (aggregated)")
  except CatchableError:
    deallocShared(outer)
    core.release(factory)
    raise
  core.release(factory)

  outer.inner = inner
  # With aggregation the outer is the identity, so the base's own view of the
  # object is an extra reference that is not ours to keep.
  if not instance.isNil and instance != cast[pointer](outer):
    discard core.release(instance)
  cast[pointer](outer)
