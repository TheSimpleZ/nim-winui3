# Lifetimes, threading and the ABI boundary

Most of what follows you can ignore while writing an app: objects are
reference-counted by the compiler and handlers are wrapped for you. It is
written down because the failure modes are quiet — a leak that takes a day to
show, or a heap corruption that fires long after the mistake — and because
anyone extending the library past the generated surface has to know the rules.

## Reference counting is the compiler's job

Every object in this library is one pointer wide. `=destroy` releases and
`=copy` retains, declared on the root of each hierarchy, which every derived
type inherits.

```nim
let label = newTextBlock("hello")
let panel = newStackPanel(Orientation_Vertical)

let text = label.text          # HSTRING converted and deleted for you
let kids = panel.children      # a reference, counted
```

There are 633 getters in the generated API that hand back a reference. Leaving
those to the caller would mean a GUI leaks one per property read, which is
about 200 bytes an iteration — invisible in a demo and fatal in a program that
runs for days. So nothing needs releasing by hand, and `tests/tlifetime.nim`
measures the counts exactly rather than guessing from process memory.

A plain `let a = b` is not necessarily a copy: Nim's ORC turns a binding that
cannot outlive its source into a cursor, which borrows rather than counts. That
is correct and costs nothing. What matters is the case where a reference really
does have to be kept — stored in a `var` or a `seq` that outlives the original
— and that case is counted.

## `owned` and `borrowed`

Raw pointers arrive from WinRT in two kinds, and the wrapper has to be told
which:

| | |
|---|---|
| `owned[T](p)` | anything a getter, factory or `QueryInterface` returned. The reference is ours; the wrapper releases it. |
| `borrowed[T](p)` | an event's `sender` and `args`. They belong to XAML for the duration of the call. The wrapper adds a reference so that releasing it later balances. |

Getting this backwards is the one remaining way to corrupt the heap from Nim
code. `Panel(p: somePointer)` is the raw form and *adopts* the reference — use
it only when you genuinely own one:

```nim
let label = newTextBlock("not a panel")

# wrong: this adopts a reference the scope never took, so the temporary's
# destructor releases one that was never ours
discard Panel(p: label.p).children

# right
discard borrowed[Panel](label.p).children
```

## Elements in the visual tree

`UIElementCollection.Append` does *not* AddRef the element. XAML owns tree
children through its own peer system rather than through COM, so an element
stays alive and usable after every Nim reference to it is gone:

```nim
let panel = newStackPanel(Orientation_Vertical)

block:
  let label = newTextBlock("parented, then abandoned")
  panel.add label
# the label is still in the tree, and still says what it said
```

## Strings

A WinRT method that returns a string hands over ownership: the `HSTRING` is the
caller's to delete. The generated API's `takeString` does that on every string
property read. Calling the ABI layer directly, you have to.

## Delegates

A WinRT delegate's vtable is four slots — `QueryInterface`, `AddRef`,
`Release`, `Invoke`. Assuming the usual six puts `Invoke` at slot 6 and calls
into whatever follows the table.

Nim closures are kept in a module-level table in `winrt`, not inside the
manually allocated COM object. A closure's environment is GC-managed and the
COM object is not; burying one in the other gives you a callback into freed
memory some minutes after it starts working. Slots are recycled through a free
list, so subscribing and unsubscribing in a loop does not grow the table —
`tests/tlifetime.nim` runs 5,000 cycles and asserts the table is the same size
afterwards.

## Nothing is released after the runtime shuts down

A wrapper captured by a handler's closure outlives the message loop: the
closure sits in that module-level table, which Nim destroys at *process* exit,
by which point XAML has freed its objects. Releasing then exits with
`STATUS_HEAP_CORRUPTION` *after* the program has printed its successful output,
which is a genuinely horrible thing to debug.

`start` therefore calls `endRuntime()` on the way out, and `releaseIfLive`
makes destructors stop releasing. This is also why `tests/run.ps1` reports the
process exit code and not just the output: a suite can print `PASS` and still
corrupt the heap on the way out, and only the exit code catches that.

## Exceptions never cross the ABI

A Nim exception must not unwind into WinUI's C++ — the behaviour is undefined.
Every callback this library installs catches `CatchableError`.

The obvious next step, returning `E_FAIL`, is wrong. XAML treats a failure out
of its own event dispatch as fatal and tears the process down, so one bug in
one handler would end the application with nothing in the log. Instead the
exception is caught, reported to stderr, flushed, and the event reported as
handled. `tests/terrors.nim` raises from a handler a hundred times and checks
that all hundred calls happened and the app still works.

## Threading

XAML objects may only be created and used on the UI thread, inside the callback
given to `start`. Constructing one earlier fails with `RPC_E_WRONG_THREAD`, and
touching one from another thread afterwards fails the same way.

`start` initialises the apartment itself rather than leaving it to the caller,
because getting it wrong surfaces as `RPC_E_CHANGED_MODE` somewhere far from
the cause. If the calling thread is already in a multi-threaded apartment,
`start` says so in those words rather than passing the HRESULT along.

A process hosts one XAML application and one UI thread. A second `start` would
deadlock rather than fail cleanly, so it is refused outright.

## Summary of what can still bite

- Passing a pointer for the wrong interface into the ABI layer — the callee is
  entitled to use it as what it declared. Use `queryInterface`.
- Adopting a borrowed pointer, or borrowing an owned one.
- Calling a slot on a pointer you did not `queryInterface` for that interface.
- Touching XAML from a thread that is not the UI thread.

Everything above the generated API handles all four for you.
