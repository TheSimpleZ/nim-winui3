## A WinUI 3 app written entirely against the generated API.
##
## Nothing here names an IID, a vtable slot, an HSTRING or a QueryInterface.
## Every type, property, constructor and event below was emitted from
## `Microsoft.UI.Xaml.winmd`; the only hand-written pieces are `start`, which
## owns the message loop, and `collections`, because a generic interface's IID
## is computed rather than declared.

from ../src/winui3 import start
import ../src/winui3/generated/xaml_api
import ../src/winui3/collections

proc brush(r, g, b: uint8, alpha = 1.0): SolidColorBrush =
  result = newSolidColorBrush()
  result.color = Color(a: 255, r: r, g: g, b: b)
  # Opacity belongs on the brush, not the element: `UIElement.Opacity` fades
  # the whole subtree, so a translucent card would take its own text with it.
  result.opacity = alpha

when isMainModule:
  start(proc() =
    let window = newWindow()
    window.title = "winui3 for Nim"
    # Mica is the material Windows 11's own Settings app uses.
    window.systemBackdrop = newMicaBackdrop()

    let page = newStackPanel()
    page.orientation = Orientation_Vertical
    page.spacing = 12.0
    page.margin = Thickness(left: 40.0, top: 32.0, right: 40.0, bottom: 32.0)

    let heading = newTextBlock()
    heading.text = "Built from metadata"
    heading.fontSize = 32.0

    let subtitle = newTextBlock()
    subtitle.text = "894 classes, 4881 procs and 417 events, " &
                    "generated from Microsoft.UI.Xaml.winmd"
    subtitle.fontSize = 14.0
    subtitle.opacity = 0.7
    subtitle.margin = Thickness(left: 0.0, top: 0.0, right: 0.0, bottom: 16.0)

    let count = newTextBlock()
    count.text = "Not clicked yet"
    count.fontSize = 18.0

    let button = newButton()
    let caption = newTextBlock()
    caption.text = "Click me"
    button.content = caption.p

    var clicks = 0
    button.onClick proc(sender: pointer, args: RoutedEventArgs) =
      clicks.inc
      count.text = "Clicked " & $clicks &
                   (if clicks == 1: " time" else: " times")

    # A rounded card, to show structs and brushes crossing the ABI.
    let card = newBorder()
    card.background = brush(255, 255, 255, alpha = 0.06)
    card.cornerRadius = CornerRadius(topLeft: 8.0, topRight: 8.0,
                                     bottomRight: 8.0, bottomLeft: 8.0)
    card.padding = Thickness(left: 20.0, top: 16.0, right: 20.0, bottom: 16.0)

    let cardBody = newStackPanel()
    cardBody.orientation = Orientation_Vertical
    cardBody.spacing = 12.0
    cardBody.add count
    cardBody.add button
    card.child = cardBody

    page.add heading
    page.add subtitle
    page.add card

    window.content = page
    window.activate()
  )
