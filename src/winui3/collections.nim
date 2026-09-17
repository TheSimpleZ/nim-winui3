## `IVector<T>` for the generated types.
##
## WinUI's collections — `Panel.Children`, `ResourceDictionary.MergedDictionaries`,
## `ItemsControl.Items` — are generic instantiations, and a generic interface's
## IID is *computed* from its type arguments rather than declared in the
## metadata. So the generators have nothing to emit for them, and this is
## written by hand.
##
## That costs less than it sounds. The pointer a property like `Children` hands
## back already *is* the correctly-parameterised interface, so no
## QueryInterface is needed — only the slot. And the slots are fixed for every
## `IVector<T>`, because they come from the interface's own definition, which
## `winrt/foundation` has read out of `Windows.winmd` as `Slot_IVector_1_*`.
##
## They are taken from there rather than written down here. `InsertAt` (11) and
## `RemoveAt` (12) are adjacent, transposing them is silent, and a comment
## claiming otherwise is exactly how that happened once already.
##
## Only the useful ones are exposed here; the rest are a slot number away.

import winrt/core
import ./generated/xaml_api

# The signatures `winrt/foundation` leaves unmapped, because they mention the
# element type `T`. An interface is a pointer however it was declared, so the
# shapes are still knowable.
type
  FnItem = proc(self, item: pointer): HRESULT {.stdcall.}
  FnIndexItem = proc(self: pointer, index: uint32,
                     item: pointer): HRESULT {.stdcall.}
  FnIndexOut = proc(self: pointer, index: uint32,
                    value: ptr pointer): HRESULT {.stdcall.}

proc add*(collection: UIElementCollection, child: UIElement) =
  ## Append a child to a panel.
  if collection.p.isNil:
    raise newException(WinRtError, "winui3: collection is nil")
  vcall(collection.p, Slot_IVector_1_Append, FnItem)(collection.p, child.p)
    .check("UIElementCollection.Append")

proc insert*(collection: UIElementCollection, index: Natural, child: UIElement) =
  ## Insert a child at `index`, shifting the rest along.
  vcall(collection.p, Slot_IVector_1_InsertAt, FnIndexItem)(
    collection.p, uint32(index), child.p).check("UIElementCollection.InsertAt")

proc delete*(collection: UIElementCollection, index: Natural) =
  ## Remove the child at `index`.
  ##
  ## Named `delete` rather than `remove` to match `system.delete` on a `seq`,
  ## which is what it does.
  vcall(collection.p, Slot_IVector_1_RemoveAt, Fn_IVector_1_RemoveAt)(
    collection.p, uint32(index)).check("UIElementCollection.RemoveAt")

proc clear*(collection: UIElementCollection) =
  ## Remove every child.
  vcall(collection.p, Slot_IVector_1_Clear, Fn_IVector_1_Clear)(collection.p)
    .check("UIElementCollection.Clear")

proc len*(collection: UIElementCollection): int =
  ## How many children the collection holds.
  if collection.p.isNil: return 0
  var n: uint32
  vcall(collection.p, Slot_IVector_1_get_Size, Fn_IVector_1_get_Size)(
    collection.p, n.addr).check("UIElementCollection.Size")
  int(n)

proc `[]`*(collection: UIElementCollection, index: Natural): UIElement =
  ## The child at `index`.
  var item: pointer
  vcall(collection.p, Slot_IVector_1_GetAt, FnIndexOut)(
    collection.p, uint32(index), item.addr).check("UIElementCollection.GetAt")
  UIElement(p: item)

iterator items*(collection: UIElementCollection): UIElement =
  ## Walk the children, so `for child in panel.children` works.
  for i in 0 ..< collection.len:
    yield collection[i]

proc add*(panel: Panel, child: UIElement) =
  ## Append straight to a panel, without naming `children`.
  panel.children.add child
