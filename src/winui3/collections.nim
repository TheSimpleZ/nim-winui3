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
## `IVector<T>`, because they come from the interface's own definition:
##
##   6  GetAt        9  IndexOf      12 InsertAt   15 Clear
##   7  get_Size    10  SetAt        13 Append     16 GetMany
##   8  GetView     11  RemoveAt     14 RemoveAtEnd 17 ReplaceAll
##
## Only the useful ones are exposed here; the rest are a slot number away.

import winrt/core
import ./generated/xaml_api

const
  SlotGetAt = 6
  SlotGetSize = 7
  SlotRemoveAt = 11
  SlotInsertAt = 12
  SlotAppend = 13
  SlotClear = 15

type
  FnItem = proc(self, item: pointer): HRESULT {.stdcall.}
  FnIndexItem = proc(self: pointer, index: uint32,
                     item: pointer): HRESULT {.stdcall.}
  FnIndexOut = proc(self: pointer, index: uint32,
                    value: ptr pointer): HRESULT {.stdcall.}
  FnIndex = proc(self: pointer, index: uint32): HRESULT {.stdcall.}
  FnSize = proc(self: pointer, value: ptr uint32): HRESULT {.stdcall.}
  FnVoid = proc(self: pointer): HRESULT {.stdcall.}

proc add*(collection: UIElementCollection, child: UIElement) =
  ## Append a child to a panel.
  if collection.p.isNil:
    raise newException(WinRtError, "winui3: collection is nil")
  vcall(collection.p, SlotAppend, FnItem)(collection.p, child.p)
    .check("UIElementCollection.Append")

proc insert*(collection: UIElementCollection, index: Natural, child: UIElement) =
  ## Insert a child at `index`, shifting the rest along.
  vcall(collection.p, SlotInsertAt, FnIndexItem)(
    collection.p, uint32(index), child.p).check("UIElementCollection.InsertAt")

proc delete*(collection: UIElementCollection, index: Natural) =
  ## Remove the child at `index`.
  ##
  ## Named `delete` rather than `remove` to match `system.delete` on a `seq`,
  ## which is what it does.
  vcall(collection.p, SlotRemoveAt, FnIndex)(collection.p, uint32(index))
    .check("UIElementCollection.RemoveAt")

proc clear*(collection: UIElementCollection) =
  ## Remove every child.
  vcall(collection.p, SlotClear, FnVoid)(collection.p)
    .check("UIElementCollection.Clear")

proc len*(collection: UIElementCollection): int =
  ## How many children the collection holds.
  if collection.p.isNil: return 0
  var n: uint32
  vcall(collection.p, SlotGetSize, FnSize)(collection.p, n.addr)
    .check("UIElementCollection.Size")
  int(n)

proc `[]`*(collection: UIElementCollection, index: Natural): UIElement =
  ## The child at `index`.
  var item: pointer
  vcall(collection.p, SlotGetAt, FnIndexOut)(
    collection.p, uint32(index), item.addr).check("UIElementCollection.GetAt")
  UIElement(p: item)

iterator items*(collection: UIElementCollection): UIElement =
  ## Walk the children, so `for child in panel.children` works.
  for i in 0 ..< collection.len:
    yield collection[i]

proc add*(panel: Panel, child: UIElement) =
  ## Append straight to a panel, without naming `children`.
  panel.children.add child
