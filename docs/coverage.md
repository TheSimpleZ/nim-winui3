# What is and is not mapped

## The ABI layer: 99%

8,968 of 8,995 vtable slots have a typed signature. The 27 that do not are all
methods taking or returning an array. They still get a `Slot_*` constant, so
they can be called with a hand-written signature:

```
# Fn_ISelectionProvider_GetSelection: signature not mapped
const Slot_ISelectionProvider_GetSelection* = 7
```

Every IID, every slot number and every enum value in this library comes out of
the metadata. Nothing transcribes one by hand.

## The API layer: 465 skipped wrappers

894 classes, 4,980 procs, 510 constructors and 635 events are generated. 465
members are skipped, and the generator says why. The largest groups:

| count | reason |
|---|---|
| 191 | the member's type is an interface declared in another winmd |
| 117 | `IReference<T>` — a nullable value, which wants an `Option[T]` |
| 65 | `IVector<T>` |
| 18 | `IVectorView<T>` |
| 17 | an array |
| 13 | a second out-parameter |
| 12 | `IAsyncOperation<T>` |
| 8 | `IMapView<K,V>` |
| 7 | `IObservableVector<T>` |
| 7 | `IIterable<T>` |
| 4 | `TypedEventHandler<A,B>` |

A generic is deliberately *not* mapped to a bare `pointer` at this level, even
though the ABI layer spells it that way. It would read as a typed API while
giving none of the safety: nothing would stop you passing a `IVector<Brush>`
where `IVector<UIElement>` was meant, and the result is a wrong vtable rather
than a type error. The honest mapping is a typed collection or an optional, and
that is work this does not do yet.

Anything skipped is still reachable through the ABI layer, which has the slot
and the IID.

## Collections

Only `UIElementCollection` has a typed wrapper, in `collections.nim`. The
others — `ItemsControl.Items`, `ResourceDictionary.MergedDictionaries`, and the
rest — work through the same slots and need the same sixty lines each.

The reason there is no generated answer is that a generic interface's IID is
*computed* from its type arguments rather than declared in any metadata file,
so a generator has nothing to read. See
[bindings.md](bindings.md#what-a-winmd-is).

## Not attempted

**XAML markup, and data binding.** This library builds trees in code. `.xaml`
files are not read, and `x:Bind` and `{Binding}` do not exist. Wiring up a
`TextBlock` in a handler is what you do instead.

**More than one window per process.** `start` runs a single XAML application
and refuses a second. A second message loop would deadlock rather than fail
cleanly.

**Custom controls with XAML templates.** Deriving from `Control` and giving it
a template means a metadata provider that knows about your types, which is a
real piece of work. Composing existing controls in code works today.

## Roadmap

The path to broader coverage is the generator, not more hand-writing. Every
real WinRT projection — C++/WinRT, C#/WinRT, windows-rs, swift-winui — is a
code generator reading `.winmd`, and this is too.

1. `IReference<T>` as `Option[T]` — 117 members, and the machinery it needs
   (computed IIDs) is already here and verified
2. Typed wrappers for `IVector<T>` and the rest of the collection family
3. A table of IIDs for interfaces declared in neighbouring winmds, the way
   `winrt`'s `foreign.nim` already does for structs and enums — 191 members
4. Arrays, and methods with a second out-parameter — 30 members
5. Generating `vendor/app.manifest` from the SDK's `package.appxfragment`
   files, rather than assembling it by hand at each SDK bump
6. Data binding, and reading `.xaml` markup

## Done

The ECMA-335 reader, the ABI generator covering IIDs, slots, enums, structs and
99% of signatures, the API generator covering 894 classes and 635 events,
computed IIDs for parameterised interfaces, compiler-managed lifetimes, system
backdrops, COM aggregation, Fluent styles, UI Automation, registration-free
deployment, and 78 checks across seven test binaries.
