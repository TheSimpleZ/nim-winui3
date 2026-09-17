## Driving the generated types through UI Automation.
##
## This exists so a GUI can be tested without a person at the keyboard.
## Synthetic mouse input cannot reach a window on a Windows desktop that is not
## the active input desktop — `SetCursorPos` there silently leaves the cursor at
## 0,0 — and switching desktops to reach it would take over the screen. Going
## through XAML's own invoke pattern raises the same `Click` a mouse would, so
## it is not a way around the event system but a way into it.
##
## It is also how assistive technology drives an application, so anything
## reachable here is reachable by a screen reader.

import winrt/core
import ./generated/xaml_abi
import ./generated/xaml_api

proc automationPeer*(element: UIElement): pointer =
  ## The UI Automation peer for an element, creating one if it has none.
  ##
  ## The caller owns the returned reference.
  ##
  ## `FromElement` declares a `UIElement` parameter and a WinRT callee may use
  ## the pointer as exactly that interface, so the element is narrowed first:
  ## handing it `IButton` instead walks `IUIElement`'s slots through the wrong
  ## vtable and takes the process down rather than returning an error.
  if element.isNil:
    raise newException(WinRtError, "winui3: element is nil")
  let iel = queryInterface(element.p, IID_IUIElement)
  if iel.isNil:
    raise newException(WinRtError, "winui3: not a UIElement")
  let statics = activationFactory(
    "Microsoft.UI.Xaml.Automation.Peers.FrameworkElementAutomationPeer",
    IID_IFrameworkElementAutomationPeerStatics)
  try:
    vcall(statics, Slot_IFrameworkElementAutomationPeerStatics_FromElement,
          Fn_IFrameworkElementAutomationPeerStatics_FromElement)(
            statics, iel, result.addr)
      .check("FrameworkElementAutomationPeer.FromElement")
    if result.isNil:
      # An element never asked for a peer does not have one yet.
      vcall(statics, Slot_IFrameworkElementAutomationPeerStatics_CreatePeerForElement,
            Fn_IFrameworkElementAutomationPeerStatics_CreatePeerForElement)(
              statics, iel, result.addr)
        .check("FrameworkElementAutomationPeer.CreatePeerForElement")
  finally:
    release(statics)
    release(iel)

proc invoke*(element: UIElement) =
  ## Press a control the way an assistive technology would.
  ##
  ## A `Button` raises a real `Click`, so every handler runs.
  ##
  ## Note that `IInvokeProvider.Invoke` allocates about 157 bytes inside XAML
  ## on every call and does not give them back — measured in
  ## `tests/tleakhunt.nim`, with the peer lookup and pattern query below at
  ## exactly zero. That is WinUI's own behaviour on the automation path, not
  ## this library's, and a user pressing the button does not go through it. It
  ## is only worth knowing if you drive a UI through automation in a loop for a
  ## long time.
  let peer = element.automationPeer()
  if peer.isNil:
    raise newException(WinRtError, "winui3: element has no automation peer")
  let ap = queryInterface(peer, IID_IAutomationPeer)
  release(peer)
  if ap.isNil:
    raise newException(WinRtError, "winui3: peer is not an AutomationPeer")

  var pattern: pointer
  try:
    vcall(ap, Slot_IAutomationPeer_GetPattern,
          proc(self: pointer, a1: int32,
               value: ptr pointer): HRESULT {.stdcall.})(
            ap, int32(PatternInterface_Invoke), pattern.addr)
      .check("AutomationPeer.GetPattern(Invoke)")
  finally:
    release(ap)
  if pattern.isNil:
    raise newException(WinRtError, "winui3: element does not support Invoke")

  let provider = queryInterface(pattern, IID_IInvokeProvider)
  release(pattern)
  if provider.isNil:
    raise newException(WinRtError, "winui3: Invoke pattern is not an IInvokeProvider")
  try:
    vcall(provider, Slot_IInvokeProvider_Invoke,
          proc(self: pointer): HRESULT {.stdcall.})(provider)
      .check("IInvokeProvider.Invoke")
  finally:
    release(provider)

proc actualSize*(element: FrameworkElement): tuple[width, height: float64] =
  ## The size layout gave this element, in effective pixels.
  ##
  ## Zero until a layout pass has run, which happens after the window is
  ## activated. This is the honest way to check that a tree laid out: a
  ## composited window captures as a black rectangle whenever the display is
  ## asleep, which no screenshot can tell apart from a control that never
  ## rendered.
  (element.actualWidth, element.actualHeight)
