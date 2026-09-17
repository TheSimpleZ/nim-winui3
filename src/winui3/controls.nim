## Conveniences on top of the generated control types.
##
## Everything here could be written by hand against `generated/xaml_api`; it is
## here because it is written by hand *often*. A constructor that takes the
## text you want, an event handler that does not make you name arguments you
## will not use, and the one property — the system backdrop — that is fiddly
## enough to be worth wrapping.
##
## Nothing in this module invents a type. The types are the generated ones, so
## anything not covered here is still one `import` away.

import ./generated/xaml_abi
import ./generated/xaml_api
import ./collections

# ------------------------------------------------------------- constructors

proc newTextBlock*(text: string): TextBlock =
  ## A `TextBlock` showing `text`.
  result = newTextBlock()
  result.text = text

proc newButton*(label: string): Button =
  ## A `Button` labelled `label`.
  ##
  ## `ContentControl.Content` takes any object, so the label goes in as a
  ## `TextBlock` rather than a bare string — a string would arrive as an
  ## `IInspectable` that XAML has to box, and this is what the XAML parser
  ## does anyway.
  result = newButton()
  let caption = newTextBlock()
  caption.text = label
  result.content = caption.p

proc newStackPanel*(orientation: Orientation, spacing = 0.0): StackPanel =
  ## A `StackPanel` with an orientation, and optionally a gap between children.
  ##
  ## `orientation` has no default on purpose: with one, this would be ambiguous
  ## against the generated zero-argument `newStackPanel()`.
  result = newStackPanel()
  result.orientation = orientation
  if spacing != 0.0:
    result.spacing = spacing

# ---------------------------------------------------------------- backdrop

type
  Backdrop* = enum
    ## The system-drawn material behind a window. Mica is what Windows 11's own
    ## Settings app uses.
    noBackdrop
    mica
    acrylic

proc `backdrop=`*(w: Window, kind: Backdrop) =
  ## Set the window's system backdrop.
  ##
  ## This is what makes a window look like Windows 11 rather than a blank
  ## rectangle: the material is drawn by the compositor behind the whole
  ## window, including the title bar.
  case kind
  of noBackdrop:
    w.systemBackdrop = SystemBackdrop()
  of mica:
    w.systemBackdrop = newMicaBackdrop()
  of acrylic:
    w.systemBackdrop = newDesktopAcrylicBackdrop()

# ------------------------------------------------------------------ events

proc onClick*(b: ButtonBase, handler: proc()): EventRegistrationToken
              {.discardable.} =
  ## Run `handler` when the button is pressed.
  ##
  ## The generated `onClick` passes the sender and the event arguments; most
  ## handlers want neither, and a closure that ignores both of them reads
  ## worse than one that was never given them.
  b.onClick(proc(sender: pointer, args: RoutedEventArgs) = handler())

proc onLoaded*(e: FrameworkElement, handler: proc()): EventRegistrationToken
               {.discardable.} =
  ## Run `handler` once the element is in the live visual tree.
  ##
  ## This is the first moment `actualSize` means anything, because layout has
  ## not run before it.
  e.onLoaded(proc(sender: pointer, args: RoutedEventArgs) = handler())

# ------------------------------------------------------------------- panels

proc add*(panel: Panel, first, second: UIElement,
          rest: varargs[UIElement]) =
  ## Append several children in one call.
  ##
  ## Two named parameters before the varargs, so that the single-child `add` in
  ## `collections` stays the better match for one argument rather than this
  ## being ambiguous with it.
  panel.children.add first
  panel.children.add second
  for child in rest:
    panel.children.add child
