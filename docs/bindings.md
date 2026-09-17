# Regenerating the bindings

Everything under `src/winui3/generated/` is emitted from
`vendor/Microsoft.UI.Xaml.winmd`. It is committed on purpose — a consumer
should not need the metadata or the generators to build, and a diff on those
files is how a Windows App SDK upgrade becomes reviewable — but it is not
hand-editable. An edit there survives exactly until the next regeneration.

## Running the generators

```
nimble bindings
```

The generators live in the `winrt` package rather than here, because what they
do is project WinRT metadata and nothing about them is specific to XAML. The
task therefore expects the [winrt repository](https://github.com/TheSimpleZ/winrt-nim)
checked out beside this one, and runs:

```
generate.exe vendor/Microsoft.UI.Xaml.winmd Microsoft.UI.Xaml \
             src/winui3/generated/xaml_abi.nim winrt/core winrt/foundation

wrappers.exe vendor/Microsoft.UI.Xaml.winmd Microsoft.UI.Xaml \
             src/winui3/generated/xaml_api.nim winrt/core
```

The trailing arguments are module names, not paths. They say where the
generated code finds the runtime (`winrt/core`) and which module already
declares the `Windows.*` types this metadata refers to but does not define
(`winrt/foundation`) — `Point`, `Size`, `Rect`, `Color`, `TimeSpan` and the
rest. 2,553 methods take or return one of those, so leaving them unmapped was
never an option; they are simply not this winmd's to declare.

Both generators print a summary. The current one:

```
xaml_abi.nim            xaml_api.nim
  enums      231          classes    894
  structs     32          procs     4980  (constructors 510)
  interfaces 1917         events     635
  slots      8995         skipped    465
  typed      8968 (99%)
  unmapped     27
```

`skipped` is explained in [coverage.md](coverage.md).

## What a `.winmd` is

ECMA-335 — the same file format as a .NET assembly, with no code in it. The
`winrt` package carries its own reader (`tools/winmd.nim`) rather than shelling
out to anything: the tables it needs are `TypeDef`, `MethodDef`, `Param`,
`InterfaceImpl`, `CustomAttribute` and the blob heap holding signatures, and
reading those directly is a few hundred lines and no dependency.

Three things the metadata does *not* contain, and where each comes from
instead:

- **Vtable slot numbers.** Not stored; derived. WinRT interfaces begin with
  `IInspectable`'s six slots, so the first declared method is slot 6, and
  delegates derive from `IUnknown` and begin at slot 3. Method order within an
  interface is the declaration order in the file.
- **IIDs of parameterised interfaces.** `IVector<UIElement>` appears in no
  metadata file. WinRT builds a signature string for the instantiation —
  `pinterface({913337e9-...};rc(Microsoft.UI.Xaml.UIElement;{c3c01020-...}))` —
  and takes a version-5 UUID of it. `tools/piid.nim` reproduces that.
- **Layouts of structs from other winmds.** See `winrt/foundation`, above.

A mistake in the second of those is particularly unkind: a wrong hash is a
perfectly well-formed GUID that simply matches nothing, so `QueryInterface`
answers `E_NOINTERFACE` and the call site looks like an unimplemented feature
rather than a wrong computation. That is why `tests/tgenerics.nim` asks a live
`Panel.Children` rather than comparing against a table, and why it includes a
one-digit-different GUID as a negative control.

## Moving to a newer Windows App SDK

1. Replace `vendor/Microsoft.UI.Xaml.winmd` with the one from the new SDK.
2. Replace `vendor/app.manifest` with the merged `package.appxfragment`
   contents from the new SDK, then `nimble manifest` to recompile it into
   `src/winui3/app.res`.
3. `nimble bindings`.
4. Read the diff. Slots are stable within a major version; across one they are
   not, and the diff is where that shows up.
5. Check `deploy.nim`'s `RuntimeFiles` against what the new framework package
   contains — the list is named rather than globbed so that a rename is loud.
6. `nimble test`.

## The other tools

These answer questions about the metadata rather than emitting anything, and
all of them live in the `winrt` repository:

| tool | question |
|---|---|
| `dump.nim` | what namespaces are in this winmd, or what are this type's IIDs and slots? |
| `inspect.nim` | what are this type's bases, interfaces and activation attributes? |
| `stats.nim` | how large is the surface? |
| `structs.nim` | which unmapped structs block the most signatures? |
| `unmapped.nim` | which signatures did not map, and why? |
| `piidcheck.nim` | what is the computed IID of this parameterised interface? |
| `foreign.nim` | emit the structs and enums that belong to a neighbouring winmd |
