# winui3

WinUI 3 desktop applications in Nim, straight against the WinRT ABI.

No C++, no C#, no XAML markup, no projection toolchain — a Nim program calls
`RoGetActivationFactory`, dispatches through COM vtables, and implements the
callbacks WinUI invokes.

![A WinUI 3 window created from Nim](docs/generated.png)

*Mica, Fluent controls, a translucent rounded card and a working click
handler — `examples/generated.nim`, written against generated bindings.*

```nim
import winui3

start proc() =
  let window = newWindow()
  window.title = "Hello from Nim"
  window.backdrop = mica          # the material Windows 11 Settings uses
  window.content = newTextBlock("WinUI 3, from Nim")
  window.activate()
```

## Status: v1.6.0

One import, a generated API covering the whole of `Microsoft.UI.Xaml`, objects
whose lifetimes the compiler manages, and a test suite that runs a real window
on its own Windows desktop.

**Working**

- **The whole `Microsoft.UI.Xaml` surface, generated.** 894 classes, 4980
  procs, 510 constructors and 635 events, emitted from
  `Microsoft.UI.Xaml.winmd` — properties as properties, `string` rather than
  `HSTRING`, typed enums, structs by value, typed event handlers, and WinUI's
  real inheritance chain. Under it, 1917 IIDs and 8995 vtable slots covering
  **99%** of all signatures, plus 231 enums and 32 structs. Nothing in this
  library transcribes a GUID, a slot number or an enum value by hand.
- **Computed IIDs for parameterised interfaces.** `IVector<UIElement>` has no
  GUID in any metadata file; WinRT derives one by hashing a signature string.
  `tools/piid.nim` reproduces that, which is what makes 218 of those 635 events
  generatable at all. It is checked against a live object rather than by
  eye — a wrong hash is a well-formed GUID that simply matches nothing.
- **Lifetimes the compiler handles.** Every object is one pointer wide and
  reference-counted through `=destroy` and `=copy`. Reading a property does not
  leak, storing a reference does not dangle, and nothing needs releasing by
  hand. 60,000 build-and-teardown cycles move private bytes, kernel handles,
  GDI and USER objects by exactly zero.
- **Fluent styles, Mica and Acrylic** — the materials that make a window look
  like Windows 11 rather than a blank rectangle. A themed `Button` measures 32
  effective pixels tall; an unstyled one collapses to nothing, which is how the
  tests tell the difference.
- **Events**, with a typed handler and an unsubscribe token. An exception in a
  handler is contained and reported rather than ending the process.
- **COM aggregation** for deriving from `Application`, and composable
  construction for the rest of the visual tree.
- **Registration-free deployment**: no installer, no framework package, no
  bootstrapper. The manifest embeds into the executable.
- **UI Automation**, so a GUI can be driven and asserted on without a person
  at the keyboard.

**Not yet**

- **27 of 8995 ABI signatures are unmapped** — all of them methods taking or
  returning an array. Those still get a slot constant and can be called with a
  hand-written signature.
- **465 wrapper procs are skipped**, and the generator says why:

  | count | reason |
  |---|---|
  | 191 | an interface declared in another winmd |
  | 117 | `IReference<T>` — a nullable value, which wants an `Option[T]` |
  |  97 | `IVector`/`IVectorView`/`IIterable`/`IObservableVector` |
  |  21 | `IAsyncOperation`, `IMap`, `IMapView` |
  |  17 | an array |
  |  13 | a second out-parameter |

  A generic is deliberately *not* mapped to a bare `pointer` at this level,
  even though the ABI layer spells it that way: it would read as a typed API
  while giving none of the safety. The honest mapping is a typed collection or
  an optional, and that is work this does not do yet.
- **Data binding, and XAML markup of any kind.** This library builds trees in
  code. `x:Bind`, `{Binding}` and `.xaml` files are not read.
- **Only `UIElementCollection` has a typed collection wrapper.** The other
  `IVector<T>`s work through the same slots and need the same sixty lines.
- **One window per process.** `start` runs a single XAML application and
  refuses a second.

## Requirements

- Windows 10 1809 or later, x64
- Nim 2.0+

The Windows App SDK is staged for you at build time; see Deployment.

## Deployment

Nothing to do. Write a file, build it, run it:

```nim
import winui3

start proc() =
  let window = newWindow()
  window.title = "Just works"
  window.backdrop = mica
  window.content = newTextBlock("No configuration, no staging step.")
  window.activate()
```

```
nim c -r myapp.nim
```

Importing `winui3` does the two things a WinUI 3 app needs and no one enjoys
doing by hand:

- **stages the Windows App SDK** into your output directory — 31 files, ~54 MB
- **links the manifest** naming the ~1840 classes it activates, as a resource
  inside your executable

Both happen at compile time. The first build copies the runtime; later builds
skip what is already current. `-d:winui3NoAutoStage` turns the staging off if
you want to manage it yourself.

Shipping is then a folder: your exe and the DLLs beside it. Nothing is
installed on the user's machine, and it runs on any Windows 10 1809 or later.

### Where those 54 MB come from

The Windows App SDK, not this library — WinUI 3 is not part of Windows. Every
WinUI 3 app pays it one way or another; the Rust `windows-reactor` crate
advertises a "single ~3 MB binary" and its build script stages 28 DLLs and
50 MB beside that binary, which is the same arrangement.

The staging source is the framework package Windows has already put on the
machine (`C:\Program Files\WindowsApps`), so there is no download. On a stock
Windows 11 it is present because the inbox Photos app depends on it; if it is
absent, the build says so and tells you what to install.

### What this costs you

The SDK travels with your app, so a security fix in it reaches your users when
you rebuild, not before. Letting Windows service the runtime instead means
packaging as MSIX with a framework dependency — real, documented, and a
different project: it needs a signing certificate, and it is not what this
library sets up for you.

## Testing

```
nimble test
```

`tests/run.ps1` builds each suite and runs it on a Windows desktop of its own,
so the windows never take your focus. Each exits by itself, and the runner
reports **the process exit code as well as the output** — a suite can print
`PASS` and still corrupt the heap on the way out, and only the exit code
catches that.

| suite | what it holds down |
|---|---|
| `tui` | an app as the README writes one: theme, layout, events |
| `tgenerated` | the generated layer: constructors, properties, enums, inheritance |
| `tstructs` | every by-value struct, round-tripped — a layout mismatch here is silent |
| `tlifetime` | reference counts, measured exactly, and delegate slot reuse |
| `tgenerics` | computed IIDs, against a live object, with a negative control |
| `terrors` | nil objects, wrong interfaces, and exceptions thrown in user callbacks |
| `tsoak` | 60,000 build-and-teardown cycles against private bytes, handles, GDI and USER |

`tests/tleakhunt.nim` is not part of the suite: it is a measuring instrument
that prints bytes-per-iteration for each operation on its own, which is how you
find *which* call leaks once `tsoak` says something does.

Three techniques make a GUI testable unattended, and all three are worth
stealing:

**Assert on layout, not on pixels.** A composited WinUI window captures as a
black rectangle whenever the display is asleep — under a title bar that
captures perfectly, because DWM draws that. So a screenshot cannot tell "the
control did not render" from "the monitor is off". `actualSize` inside
`onLoaded` reports what the layout engine actually did, and is true regardless.
A `Button` measuring 32 effective pixels tall is also proof the Fluent template
loaded, since an unstyled one collapses to nothing.

**Click through UI Automation.** Synthetic mouse input cannot reach a window on
a desktop that is not the active input desktop: `SetCursorPos` there silently
leaves the cursor at 0,0. `invoke` goes through XAML's own invoke pattern, so a
`Button` raises a real `Click` and every handler runs — it is not a shortcut
around the event system, it is the event system.

**Measure three phases, not two.** A before-and-after memory reading cannot
tell a leak from an allocator holding freed pages. A leak is *linear*: the
third phase costs what the second did. That distinction is what turned "4 MB,
probably fine" into a real missing `WindowsDeleteString`.

## Design notes

**Everything is positional.** A WinRT interface is a pointer to a pointer to a
table of function pointers, and which method you called is decided by counting.
No IID or slot index is written by hand: both come from
`generated/xaml_abi.nim`, emitted from the winmd. Slots are stable within an
SDK major version and are not guaranteed across one, so a new SDK means
regenerating rather than auditing call sites.

**The WinRT layer knows nothing about XAML.** `core.nim` imports only the
standard library and `delegate.nim` imports only `core`; the generators take a
namespace prefix as an argument. Pointing them at `Windows.winmd` with
`Windows.Gaming.Input` produces working gamepad bindings — `IID_IGamepad`,
`getCurrentReading` — with no change to any of it. That is the
`winim`/`wNim` shape: a binding layer that happens to have a GUI framework
built on it, rather than one thing that only does XAML.

**Delegates are `IUnknown`, not `IInspectable`.** A WinRT delegate's vtable is
four slots — QueryInterface, AddRef, Release, Invoke. Assuming the usual six
puts `Invoke` at slot 6 and calls into whatever follows the table.

**Nim closures are kept in a module-level table**, not inside the manually
allocated COM object. A closure's environment is GC-managed and the COM object
is not; burying one in the other gives you a callback into freed memory some
minutes after it starts working. Slots are recycled through a free list, so
subscribing and unsubscribing in a loop does not grow the table.

**Reference counting is the compiler's job.** `=destroy` releases and `=copy`
retains, on the root of each hierarchy, which every derived type inherits.
There are 633 getters that hand back a reference; leaving those to the caller
would mean a GUI leaks one per property read. `owned[T]` and `borrowed[T]` say
which of the two kinds of raw pointer you have — anything a getter, factory or
QueryInterface returned is *owned*, an event's sender and arguments are *lent*
— and getting that backwards is the one remaining way to corrupt the heap.

**An event handler never returns a failing HRESULT.** A Nim exception must not
unwind into WinUI's C++, so the obvious design is to catch it and return
`E_FAIL`. XAML treats a failure out of its own event dispatch as fatal and
tears the process down, so one bug in one handler would end the application
with nothing in the log. The exception is caught, reported to stderr, flushed,
and the event reported as handled.

**Nothing is released after the runtime shuts down.** A wrapper captured by a
handler's closure outlives the message loop: the closure sits in that
module-level table, which Nim destroys at *process* exit, by which point XAML
has freed its objects. Releasing then exits with `STATUS_HEAP_CORRUPTION`
*after* the program has printed its successful output. `start` marks the
runtime gone on the way out, and destructors stop releasing.

**XAML objects may only be created on the UI thread**, inside the `start`
callback. Earlier construction fails with `RPC_E_WRONG_THREAD`.

**Exceptions never cross the ABI.** Handler bodies are wrapped; a Nim exception
unwinding into WinUI's C++ is undefined behaviour.

**Slots are per-interface, not per-object.** `Children` lives on `IPanel`, so
calling `Slot_IPanel_get_Children` through an `IStackPanel` pointer reaches
slot 6 of the *wrong* vtable — `get_AreScrollSnapPointsRegular` — which returns
`S_OK` while writing a bool where a pointer was expected. Nothing reports an
error; you just get nothing back. QueryInterface first, always.

**Structs cross by value, so the layout has to be exact.** `Thickness` is four
`float64`s and `Color` is four bytes with alpha first; a wrong field order or
width does not raise, it silently shifts every field. The in-namespace ones are
read straight out of the metadata. `Point`, `Rect`, `Color` and the rest live in
winmd files this project does not ship, so `tools/foreign.nim` writes them out
once, with their source named — 2,553 methods take or return one, so leaving
them unmapped was not an option. Nim emits them as plain C structs, which means
the C compiler applies the same x64 convention WinUI's own C++ was built with.

**Generic collections stay hand-written.** A generic interface's IID is
*computed* from its type arguments rather than declared, so there is nothing in
the metadata for a generator to emit. `collections.nim` covers it in sixty
lines, because the pointer a property like `Children` returns already *is* the
correctly-parameterised interface — only the slot is needed, and `IVector<T>`
numbers its slots the same way whatever `T` is.

**A parameterised interface's IID is computed, not declared.** `IVector<T>`
appears in no metadata file, so there is nothing to read. WinRT builds a
signature string for the instantiation — `pinterface({913337e9-...};rc(
Microsoft.UI.Xaml.UIElement;{c3c01020-...}))` — and takes a version-5 UUID of
it. Getting a character wrong yields a perfectly well-formed GUID that no
object implements, so `QueryInterface` answers `E_NOINTERFACE` and the call
site looks like an unimplemented feature rather than a wrong hash. That is why
`tests/tgenerics.nim` asks a live `Panel.Children` rather than comparing
against a table, and why it includes a one-digit-different GUID as a control.

**The class hierarchy is Nim's own inheritance, not converters.** Modelling
894 classes as `distinct pointer` plus a `converter` to each ancestor is the
obvious first design and is unusable: Nim considers every converter in scope at
every type mismatch, and 1,715 of them took one module from 3.6 seconds to over
seven minutes to compile. Plain object inheritance costs nothing, passes a
derived value where a base is expected, and resolves inherited methods; with
`{.inheritable, pure.}` there is no runtime type field, so each wrapper is
exactly one pointer wide.

**The generated API is emitted per declaring class, not per class.** A method
lives on whichever class's own interfaces declare it and reaches subclasses
through inheritance. Emitting the full inherited surface for every class
instead would mean 94,521 procs rather than 4,458, for exactly the same API.

**Interface parameters name the interface they want.** Every WinRT interface
is a bare `pointer` at the ABI, so nothing in the type system stops you passing
`IButton` where `UIElement` was declared — and a callee is entitled to use the
pointer as exactly what it declared, so the wrong vtable is not an error, it is
a crash. The generator therefore names such parameters after their interface:
`Fn_IWindow_put_Content` reads `a1UIElement: pointer`, not `a1: pointer`. Use
`withInterface` to satisfy them.

**Enum values come from the winmd too.** XAML numbers `Orientation` as
`Vertical = 0, Horizontal = 1`; WPF numbers the same-named enum the other way
round. Writing one out by hand costs a panel that lays out sideways and reports
nothing wrong — `get_Orientation` reads back exactly what you set. All 231
enums are generated as `distinct int32` rather than Nim `enum`s, because WinRT
enums are sparse, sometimes flags, and sometimes give one value two names.

**A black screenshot is usually not a rendering bug.** A WinUI window is
composited, so `PrintWindow` returns a black client area whenever the display
is asleep — under a title bar that captures perfectly, because DWM draws that.
Ask the layout engine instead: `actualSize` inside `onLoaded` is true whatever
the display is doing, and a `Button` reporting 32px tall is also proof the
Fluent styles loaded.

**Most of XAML is composable, not activatable.** Types designed to be derived
from — `MicaBackdrop`, and most of the visual tree — answer `RoActivateInstance`
with `E_NOTIMPL`. They are built through their factory's
`CreateInstance(outer, inner, value)`, and the `inner` pointer it hands back
carries its own reference that has to be released.

## Roadmap

The path to broad coverage is a generator, not more hand-writing. Every real
WinRT projection — C++/WinRT, C#/WinRT, windows-rs, swift-winui — is a code
generator reading `.winmd`, and this should be too.

1. `IReference<T>` as `Option[T]` — 117 methods, and the machinery it needs
   (computed IIDs) is already here and verified
2. Typed wrappers for `IVector<T>` and the rest of the collection family
3. A table of IIDs for interfaces declared in neighbouring winmds, the way
   `tools/foreign.nim` already does for structs and enums
4. Arrays, and methods with a second out-parameter
5. Manifest generation from `package.appxfragment`

4. Data binding, and reading `.xaml` markup

Done: the ECMA-335 reader (`src/winui3/winmd.nim`), the ABI generator
(`tools/generate.nim`) covering IIDs, slots, enums, structs and 99% of
signatures, the API generator (`tools/wrappers.nim`) covering 894 classes and 635 events,
computed IIDs for parameterised interfaces, compiler-managed lifetimes, system
backdrops, COM aggregation, Fluent styles, UI Automation, and a suite of 77
checks across seven binaries.

## Regenerating

```
nimble bindings
```

which runs both generators against `vendor/Microsoft.UI.Xaml.winmd`:

```
nim c -r tools/generate.nim <winmd> <prefix> src/winui3/generated/xaml_abi.nim
nim c -r tools/wrappers.nim <winmd> <prefix> src/winui3/generated/xaml_api.nim
```

The other tools answer questions about the metadata rather than emitting
anything: `dump.nim` lists namespaces, or the IIDs and slots of a named type;
`inspect.nim` shows one type's bases, interfaces and activation attributes;
`stats.nim` counts the surface; `structs.nim` reports which structs block the
most signatures.

## Layout

```
src/winui3.nim            the one import
src/winui3/
  core.nim                HRESULT, GUID, HSTRING, activation, refcounts
  delegate.nim            COM objects WinUI calls back into
  lifecycle.nim           start, exitApp, the Fluent theme
  deploy.nim              stages the SDK and links the manifest, at build time
  app.nim                 the aggregated Application
  controls.nim            conveniences over the generated types
  collections.nim         IVector<T>
  automation.nim          UI Automation, actualSize
  generated/xaml_abi.nim  IIDs, slots, enums, structs   (32k lines, generated)
  generated/xaml_api.nim  894 classes and their members (46k lines, generated)
tools/                    the generators, the ECMA-335 reader they use, and
                          tools for asking the winmd things
tests/                    six suites, plus a leak-measuring instrument
vendor/                   the winmd, the manifest, and its compiled resource
docs/                     screenshots
```

## Licence

MIT
