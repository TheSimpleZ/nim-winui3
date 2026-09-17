## Tests for structs passed by value.
##
## `Thickness`, `Color` and `GridLength` cross the ABI as values, not pointers,
## so their Nim layout has to match what WinUI's C++ was compiled against —
## field order, field types and padding alike. A mismatch does not raise: it
## silently shifts every field, so a margin of 20 comes back as something else
## or the call corrupts the stack.
##
## Every check here therefore writes a struct and reads it back.

import winui3
import ./checks

when isMainModule:
  beginSuite()
  start(proc() =
    let window = newWindow()
    window.title = "struct tests"

    let panel = newStackPanel()
    panel.orientation = Orientation.Vertical

    # Four float64s, 32 bytes: too large for a register, so the x64 ABI passes
    # it by hidden pointer. Nim emits a plain C struct, so the C compiler makes
    # that decision the same way WinUI's C++ did.
    let border = newBorder()
    border.padding = Thickness(left: 10.0, top: 20.0, right: 30.0, bottom: 40.0)
    let p = border.padding
    check("Thickness round-trips",
          p.left == 10.0 and p.top == 20.0 and p.right == 30.0 and
          p.bottom == 40.0,
          $p.left & "," & $p.top & "," & $p.right & "," & $p.bottom)

    let cr = CornerRadius(topLeft: 1.0, topRight: 2.0,
                          bottomRight: 3.0, bottomLeft: 4.0)
    border.cornerRadius = cr
    let got = border.cornerRadius
    check("CornerRadius round-trips",
          got.topLeft == 1.0 and got.bottomLeft == 4.0,
          $got.topLeft & ".." & $got.bottomLeft)

    # Four bytes, alpha first. Byte order is the whole risk here: a wrong field
    # order still compiles and still paints, just in the wrong colour.
    let brush = newSolidColorBrush()
    brush.color = Color(a: 255, r: 16, g: 32, b: 48)
    let col = brush.color
    check("Color round-trips, alpha first",
          col.a == 255 and col.r == 16 and col.g == 32 and col.b == 48,
          "a=" & $col.a & " r=" & $col.r & " g=" & $col.g & " b=" & $col.b)

    border.background = brush

    # A float64 and an enum in one struct — the mixed-field case.
    let col0 = newColumnDefinition()
    col0.width = GridLength(value: 2.0, gridUnitType: GridUnitType.Star)
    let w = col0.width
    check("GridLength round-trips",
          w.value == 2.0 and w.gridUnitType == GridUnitType.Star,
          $w.value & " " & $w.gridUnitType)

    let label = newTextBlock()
    label.text = "Structs cross by value"
    label.fontSize = 24.0
    label.margin = Thickness(left: 24.0, top: 24.0, right: 24.0, bottom: 24.0)
    let m = label.margin
    check("Margin reaches FrameworkElement through inheritance",
          m.left == 24.0 and m.bottom == 24.0, $m.left)

    border.child = label
    panel.add border
    window.content = panel
    window.activate()

    finishSuite()
  )
