# MacScheme Interrupt Handling

MacScheme runs embedded Chez Scheme on a dedicated worker thread.
That is what makes the `Scheme > Stop` command work reliably, even when Scheme code is stuck in an infinite loop.

## Quick test

This example loops forever, computing factorials starting at `7!`:

- [examples/interrupt_factorial_loop.ss](examples/interrupt_factorial_loop.ss)

Load it from the MacScheme project directory:

```scheme
(load "examples/interrupt_factorial_loop.ss")
```

Then choose `Scheme > Stop` or press `Cmd-.`.

## How it works

### 1. Scheme runs on one dedicated pthread

MacScheme does not evaluate Scheme on the Cocoa main thread.
Instead, it creates one long-lived Scheme worker thread and sends evaluation requests to it.

That matters because Chez ties keyboard interrupts to the Scheme thread context that receives the signal.
If the signal goes to the wrong thread, the interrupt will not stop the running Scheme evaluation.

### 2. `Scheme > Stop` targets that exact thread

The Stop menu item calls Objective-C code in [src/app_delegate.m](src/app_delegate.m).
That code sends `SIGINT` with `pthread_kill` to the dedicated Scheme pthread.

So the interrupt is not broadcast vaguely to the whole app.
It is delivered directly to the thread that is currently running Scheme.

### 3. Chez treats `SIGINT` as a keyboard interrupt

Inside Chez Scheme, `SIGINT` is the normal keyboard-interrupt path.
When the Scheme worker thread receives it, Chez marks a keyboard interrupt as pending.
The interrupt is then processed at a safe interrupt boundary in Scheme execution.

This is why the stop is cooperative rather than a hard thread kill:

- it does not tear down the app process
- it does not forcibly destroy the Scheme thread
- it gives Chez a chance to unwind safely

### 4. MacScheme overrides the default interrupt behavior

By default, Chez often responds to a keyboard interrupt by entering its interactive debugger/break handler.
That is good for a terminal REPL, but not ideal for an embedded GUI app.

MacScheme instead installs a temporary `keyboard-interrupt-handler` around its evaluation helpers.
That handler escapes from the current evaluation and returns a normal result shaped like an error/result pair.
In practice, that means the GUI REPL gets back a clean message like `Interrupted` instead of dropping into the Chez debugger.

### 5. `call/cc` provides the escape hatch

The evaluation helper is wrapped in `call/cc`.
When an interrupt happens, the custom `keyboard-interrupt-handler` invokes the captured continuation immediately and returns:

```scheme
(list #t "Interrupted")
```

MacScheme already uses a `(error? text)` style return convention for GUI evaluation.
So an interrupt fits neatly into the same path as other handled failures.

### 6. The REPL UI stays alive

Because only the current Scheme evaluation is aborted:

- the app window stays responsive
- the Scheme worker thread remains alive
- the REPL prints the interruption result
- MacScheme shows a fresh prompt and can evaluate the next expression normally

## Why this is better than force-killing evaluation

A hard stop, like terminating the whole app or killing the worker thread, would leave the embedded runtime in an unknown state.
Using Chez's own keyboard-interrupt mechanism is safer because it matches the runtime's expected control flow.

## Limits and expectations

This works well for normal Scheme code, including runaway recursion and ordinary infinite loops.
Like most language-level interrupt systems, it depends on Chez reaching interrupt-check points.
Very low-level code that disables interrupts or spends a long time outside normal Scheme call boundaries can delay handling.

For regular MacScheme REPL usage, though, `Cmd-.` is the right model: it interrupts the current evaluation and returns control to the prompt.

## Relevant implementation pieces

- [src/app_delegate.m](src/app_delegate.m)
  - installs the `Scheme > Stop` menu item
  - sends `SIGINT` to the Scheme pthread with `pthread_kill`
  - wraps GUI eval/load helpers with a custom `keyboard-interrupt-handler`
- [examples/interrupt_factorial_loop.ss](examples/interrupt_factorial_loop.ss)
  - simple infinite-loop test for verifying Stop behavior
