# How the library is put together

`winui3` is two generated layers with a thin hand-written lid, sitting on the
`winrt` package. Almost none of it was typed by a person, and that is the
point: WinUI 3 has 894 classes, and a binding that is hand-transcribed is a
binding that is permanently 5% finished and quietly wrong in places.

```
your program
  winui3            lifecycle, the aggregated Application, conveniences,
                    collections, UI Automation, deployment
  winui3/generated/xaml_api    894 classes, properties, events   (generated)
  winui3/generated/xaml_abi    IIDs, vtable slots, signatures    (generated)
  winrt             HSTRING, GUID, apartments, activation, refcounts,
                    the COM objects WinUI calls back into
  Windows App SDK   Microsoft.ui.xaml.dll and friends
```

## The ABI layer

`src/winui3/generated/xaml_abi.nim` is emitted from
`vendor/Microsoft.UI.Xaml.winmd`. It holds no logic at all — only facts read
out of the metadata:

| | |
|---|---|
| 1,917 | `IID_*` constants, one per interface |
| 8,995 | `Slot_*` constants, one per method |
| 8,968 | `Fn_*` types, one per method signature (99% of the slots) |
| 231 | enums, 1,278 members |
| 32 | structs passed by value |

A WinRT interface pointer points at a pointer to an array of function
pointers, and which method you called is decided by counting. So a call is a
slot and a signature:

```
vcall(iapp, Slot_IApplication_get_Resources,
      Fn_IApplication_get_Resources)(iapp, resources.addr)
```

Two properties of that arrangement are worth stating because both are silent
when violated.

**Slots are numbered per interface, not per object.** `Children` is declared on
`IPanel`. Calling `Slot_IPanel_get_Children` through an `IStackPanel` pointer
reaches slot 6 of a *different* table — `get_AreScrollSnapPointsRegular` —
which returns `S_OK` while writing a bool where a pointer was expected.
Nothing reports an error; you just get nothing back. QueryInterface first,
always. The generated API does this for you on every call.

**Slots are stable within an SDK major version and not across one.** A new
Windows App SDK means regenerating, not auditing call sites.

## The API layer

`src/winui3/generated/xaml_api.nim` is emitted from the same metadata and is
what you actually write against: 894 classes, 4,980 procs, 510 constructors and
635 events, with properties as properties, `string` rather than `HSTRING`,
typed enums, structs by value and typed event handlers.

Several decisions in it are not obvious, and each one was the second attempt.

**Classes are Nim's own inheritance, not converters.** Modelling 894 classes as
`distinct pointer` plus a `converter` to each ancestor is the obvious first
design and is unusable: Nim considers every converter in scope at every type
mismatch, and 1,715 of them took one module from 3.6 seconds to over seven
minutes to compile. Plain object inheritance costs nothing, passes a derived
value where a base is expected, and resolves inherited methods. With
`{.inheritable, pure.}` there is no runtime type field, so each wrapper is
exactly one pointer wide.

**Members are emitted per declaring class.** A method lives on whichever
class's own interfaces declare it, and reaches subclasses through inheritance.
Emitting the full inherited surface for every class instead would mean 94,521
procs rather than 4,980, for exactly the same API.

**Enum values come from the metadata.** XAML numbers `Orientation` as
`Vertical = 0, Horizontal = 1`; WPF numbers the same-named enum the other way
round. Writing one out by hand costs a panel that lays out sideways and reports
nothing wrong, because `get_Orientation` reads back exactly what you set. All
231 enums are `distinct int32` rather than Nim `enum`s, because WinRT enums are
sparse, sometimes flags, and sometimes give one value two names.

**Structs cross by value, so the layout has to be exact.** `Thickness` is four
`float64`s and `Color` is four bytes with alpha first. A wrong field order or
width does not raise — it silently shifts every field. The in-namespace ones
are read straight out of the metadata; `Point`, `Rect`, `Color` and the rest
belong to `Windows.Foundation` and come from the `winrt` package. Nim emits
them as plain C structs, so the C compiler applies the same x64 convention
WinUI's own C++ was built with.

**Interface parameters name the interface they want.** Every WinRT interface is
a bare `pointer` at the ABI, so nothing in the type system stops you passing
`IButton` where `UIElement` was declared — and a callee is entitled to use the
pointer as exactly what it declared, so the wrong vtable is not an error, it is
a crash. The generator therefore names such parameters after their interface:
`Fn_IWindow_put_Content` reads `a1UIElement: pointer`, not `a1: pointer`.

**Most of XAML is composable, not activatable.** Types designed to be derived
from — `MicaBackdrop`, and most of the visual tree — answer
`RoActivateInstance` with `E_NOTIMPL`. They are built through their factory's
`CreateInstance(outer, inner, value)`, and the `inner` pointer it hands back
carries its own reference that has to be released. The generator works out
which construction a class needs from its activation attributes, so
`newBorder()` and `newTextBlock()` look the same from outside.

## The hand-written part

| module | what it is |
|---|---|
| `lifecycle.nim` | `start`, `exitApp`, and merging the Fluent theme |
| `app.nim` | the aggregated `Application` and its XAML metadata provider |
| `deploy.nim` | stages the SDK and links the manifest, at compile time |
| `controls.nim` | conveniences: `newButton("text")`, `onClick`, `backdrop=` |
| `collections.nim` | `IVector<T>` for `UIElementCollection` |
| `automation.nim` | UI Automation — `invoke`, `actualSize` |

Two of those exist because a generator cannot produce them.

`app.nim` subclasses WinRT rather than calling it. An `Application` built with
a nil outer pointer is only half-built and answers `E_UNEXPECTED` from
`get_Resources`, so the supported construction passes our own COM object as
`outer` to `IApplicationFactory.CreateInstance` and forwards everything we do
not implement to the `inner` it hands back — what `winrt::make<App>()` does in
C++/WinRT. It must also expose `IXamlMetadataProvider`, because
`XamlControlsResources` parses `generic.xaml` and parsing XAML means resolving
type names; without one, activation fails with a bare `E_FAIL`. A COM object
exposing two interfaces cannot serve both from one vtable, so the object begins
with two vtable pointers and `QueryInterface` hands out the address of
whichever field matches.

`collections.nim` exists because a generic interface's IID is *computed* from
its type arguments rather than declared, so there is nothing in the metadata
for a generator to emit. It costs less than it sounds: the pointer a property
like `Children` returns already *is* the correctly-parameterised interface, so
only the slot is needed, and `IVector<T>` numbers its slots the same way
whatever `T` is.

## Why the WinRT half is a separate package

Nothing in `winrt` knows about XAML. Its `core` module imports only the
standard library, its `delegate` module imports only `core`, and the
generators take a namespace prefix as an argument — point them at
`Windows.winmd` with `Windows.Gaming.Input` and you get working gamepad
bindings with no change to any of it. That is the `winim`/`wNim` shape: a
binding layer that happens to have a GUI framework built on it, rather than one
thing that only does XAML.

## See also

- [Regenerating the bindings](bindings.md)
- [Lifetimes, threading and the ABI boundary](lifetimes.md)
- [What is and is not mapped](coverage.md)
