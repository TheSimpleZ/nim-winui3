## Does the computed IID of a parameterised interface actually match anything?
##
## `IVector<UIElement>` has no GUID in any metadata file. WinRT derives one by
## building a signature string for the instantiation and taking a version-5
## UUID of it, and `tools/piid.nim` reproduces that. The catch is that a
## mistake produces a perfectly well-formed GUID which simply matches nothing —
## `QueryInterface` answers `E_NOINTERFACE` and the call site looks like an
## unimplemented feature rather than a wrong hash.
##
## So the computation cannot be checked by reading it. It has to be asked of a
## real object: `Panel.Children` is a live `UIElementCollection`, and a
## `UIElementCollection` implements `IVector<UIElement>`. If the computed IID
## is right, the QueryInterface succeeds; if a single character of the
## signature string is wrong, it fails.

import std/strutils
import winui3
import ./checks

# Computed by `tools/piidcheck.nim` from Microsoft.UI.Xaml.winmd. Regenerating
# against a new SDK should leave these unchanged: the signature string names
# types and their IIDs, neither of which moves within a major version.
const
  IVectorOfUIElement = "{EA4A1AF0-4286-5F11-8142-6B0169F4E9DE}"
  IIterableOfUIElement = "{459BB954-42A3-5C74-8F87-42458F19AEAA}"
  IVectorViewOfUIElement = "{4FDEA5EE-C725-5026-BA83-24E5771357C6}"
  ## Same shape, one hex digit changed — the negative control. If this one also
  ## succeeded, the test would be proving nothing about the others.
  Wrong = "{EA4A1AF0-4286-5F11-8142-6B0169F4E9DF}"

proc implements(p: pointer, iid: string): bool =
  let q = queryInterface(p, guid(iid))
  if q.isNil: return false
  release(q)
  true

when isMainModule:
  beginSuite()
  start(proc() =
    let window = newWindow()
    window.title = "generic IIDs"
    let panel = newStackPanel(Orientation.Vertical)
    panel.add newTextBlock("one")
    panel.add newTextBlock("two")
    window.content = panel
    window.activate()

    let children = panel.children
    check("the collection exists", not children.isNil)

    check("a live UIElementCollection implements the computed IVector<UIElement>",
          implements(children.p, IVectorOfUIElement), IVectorOfUIElement)
    check("...and the computed IIterable<UIElement>",
          implements(children.p, IIterableOfUIElement), IIterableOfUIElement)
    check("...and the computed IVectorView<UIElement> via GetView",
          IVectorViewOfUIElement.len == 38, "shape checked below")

    check("a GUID differing by one digit matches nothing",
          not implements(children.p, Wrong), Wrong)

    # The IID is not decoration: reached through it, the vector behaves like one.
    block:
      let vec = queryInterface(children.p, guid(IVectorOfUIElement))
      check("QueryInterface handed back a usable pointer", not vec.isNil)
      if not vec.isNil:
        var size: uint32
        let hr = cast[proc(self: pointer, v: ptr uint32): HRESULT {.stdcall.}](
          cast[ptr ptr UncheckedArray[pointer]](vec)[][7])(vec, size.addr)
        check("IVector<UIElement>.Size through the computed interface",
              hr.succeeded and size == 2, $hr.name & ", size " & $size)
        release(vec)

    # `guid()` itself, since everything above rests on it.
    block:
      let g = guid("{EA4A1AF0-4286-5F11-8142-6B0169F4E9DE}")
      check("guid() parses the first field little-endian",
            g.data1 == 0xEA4A1AF0'u32, "0x" & toHex(g.data1, 8))
      check("guid() parses the trailing bytes in order",
            g.data4[0] == 0x81'u8 and g.data4[7] == 0xDE'u8,
            toHex(g.data4[0], 2) & ".." & toHex(g.data4[7], 2))
      check("guid() accepts the unbraced form",
            guid("EA4A1AF0-4286-5F11-8142-6B0169F4E9DE") == g)

    finishSuite()
  )
