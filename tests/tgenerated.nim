## Tests for the generated API — the layer emitted from `Microsoft.UI.Xaml.winmd`.
##
## Nothing below names an IID, a vtable slot or an HSTRING. If the generator
## gets a slot, a signature, an enum value or an inheritance edge wrong, these
## fail.
##
## Only `start` is imported from the hand-written library, because something has
## to own the message loop. Everything else is generated, so the names here
## would otherwise collide with the hand-written `Window`, `Button` and friends.

import winui3
import ./checks

when isMainModule:
  beginSuite()
  start(proc() =
    # Composable types refuse RoActivateInstance; these constructors go through
    # the factory, and the generator worked out which from the metadata.
    let window = newWindow()
    let panel = newStackPanel()
    let label = newTextBlock()
    let button = newButton()
    check("composable constructors returned objects",
          not window.isNil and not panel.isNil and not button.isNil)

    window.title = "generated api tests"
    check("string property round-trips", window.title == "generated api tests",
          window.title)

    label.text = "hello"
    label.fontSize = 28.0
    check("text round-trips", label.text == "hello", label.text)
    check("float property round-trips", label.fontSize == 28.0,
          $label.fontSize)

    # XAML numbers this enum Vertical-first; WPF numbers it the other way. The
    # value comes from the winmd, so this catches the generator reading it
    # backwards.
    panel.orientation = Orientation.Vertical
    check("enum round-trips", panel.orientation == Orientation.Vertical,
          $panel.orientation)
    check("Orientation.Vertical is 0", int32(Orientation.Vertical) == 0,
          $int32(Orientation.Vertical))

    panel.spacing = 16.0
    check("spacing round-trips", panel.spacing == 16.0, $panel.spacing)

    # `children` is declared on Panel and `label` is a TextBlock: both rely on
    # the generated inheritance chain rather than on any conversion.
    panel.add label
    panel.add button
    check("Panel.Children accepted subclass values", panel.children.len == 2,
          $panel.children.len & " children")
    check("collection indexing returns the children",
          not panel.children[0].isNil and not panel.children[1].isNil)

    # `InsertAt` and `RemoveAt` are adjacent slots on `IVector<T>`, and
    # transposing them is silent: each is a valid call on the other's
    # arguments. So both are exercised rather than assumed.
    block:
      let inserted = newTextBlock()
      inserted.text = "inserted"
      panel.children.insert(0, inserted)
      check("insert grew the collection", panel.children.len == 3,
            $panel.children.len & " children")

      let front = queryInterface(panel.children[0].p, IID_ITextBlock)
      check("insert put the child at the index given",
            not front.isNil and TextBlock(p: front).text == "inserted")

      panel.children.delete(0)
      check("delete removed it again", panel.children.len == 2,
            $panel.children.len & " children")

    # Events come out of the metadata too: the handler's shape is read from the
    # delegate's own Invoke, so this closure is typed rather than a raw pointer.
    var clicks = 0
    var lastArgs = false
    let token = button.onClick(proc(sender: pointer, args: RoutedEventArgs) =
      clicks.inc
      lastArgs = not args.isNil)
    check("onClick returned a token", token.value != 0, $token.value)

    button.invoke()
    check("generated event handler ran", clicks == 1, $clicks)
    check("handler received typed event args", lastArgs)

    button.removeClick(token)
    button.invoke()
    check("removeClick unsubscribed", clicks == 1, $clicks)

    # Window.Content is declared as UIElement; passing a StackPanel exercises
    # the same subtyping, and the wrapper QueryInterfaces internally.
    window.content = panel
    check("Window.Content accepted a StackPanel", not window.content.isNil)

    window.activate()
    check("window is visible", window.visible, $window.visible)

    finishSuite()
  )
