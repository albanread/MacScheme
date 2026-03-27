# MacScheme REPL Output Redirection

MacScheme now routes ordinary Scheme textual output into the GUI REPL instead of relying on the terminal that launched the app.
That means forms like `display`, `write`, `newline`, `printf`, `pretty-print`, and writes to `current-error-port` show up in the MacScheme window.

## Quick test

A small demo lives here:

- [examples/redirect_io_demo.ss](examples/redirect_io_demo.ss)

Load it from the MacScheme project directory:

```scheme
(load "examples/redirect_io_demo.ss")
```

You should see several lines appear in the GUI REPL, followed by the final result:

```scheme
io-demo-complete
```

## What problem this solves

Before this change, MacScheme captured the final value of an evaluation and displayed that in the GUI, but ordinary side-effect output still went to Chez Scheme's default stdout and stderr ports.
For a GUI app, that is not very useful:

- if you launched the app from a shell, output appeared in that shell
- if you launched the app from Finder, output effectively disappeared from the user's point of view

The new design keeps the final result behavior and also makes side-effect output visible in the app itself.

## How it works

### 1. Objective-C exposes two write callbacks

In [src/app_delegate.m](src/app_delegate.m), MacScheme exports two foreign functions to Chez Scheme:

- `macscheme_repl_write_output`
- `macscheme_repl_write_error`

These functions accept UTF-8 text, convert it to `NSString`, and dispatch back to the Cocoa main thread.
From there they call the existing REPL grid append path.

So the text grid remains the single UI sink for REPL text.

### 2. Chez creates two custom output ports

During Scheme initialization, MacScheme defines:

- `macscheme-gui-output-port`
- `macscheme-gui-error-port`

These are built with `make-output-port`.
Their handlers translate Scheme port operations into calls to the foreign Objective-C write callbacks.

The important messages are:

- `write-char`
- `block-write`
- `flush-output-port`
- `close-port`
- `port-name`

For actual text output, `write-char` and `block-write` forward text into the GUI.

### 3. Eval and load temporarily rebind the active ports

The embedded helpers `macscheme-eval-string` and `macscheme-load-file` already wrap each evaluation with interrupt handling and exception handling.
Now they also parameterize these ports:

- `console-output-port`
- `current-output-port`
- `console-error-port`
- `current-error-port`

That is the key step.
Most normal textual output in Chez flows through those parameters, so rebinding them causes standard REPL output to land in the MacScheme window.

### 4. Final values still use the existing result path

MacScheme still separately captures the final value of the evaluation and displays it once at the end.
So there are now two complementary paths:

- side-effect text goes through the custom GUI ports as it is produced
- the final expression result is rendered by the existing evaluation return-value path

This preserves the nice REPL behavior you already had while making side effects visible.

## Why this design fits the app

This approach matches the structure of MacScheme well:

- Scheme still runs on its dedicated worker thread
- UI updates still happen on the main thread
- the text grid remains the single source of truth for visible REPL text
- no dependency on an external terminal is required

It also avoids trying to scrape process stdout at the operating-system level.
Instead, it redirects output at the Scheme runtime level, which is more precise and more portable inside the embedded evaluator.

## Notes and limits

- This redirection applies to output produced while MacScheme evaluates code through its embedded eval/load helpers.
- Output ordering is preserved naturally because both side-effect text and the final result are queued onto the main thread in evaluation order.
- Binary output is not part of this path; this is specifically for textual Scheme ports.
- Code that explicitly opens and writes to files is unaffected, as it should be.

## Relevant files

- [src/app_delegate.m](src/app_delegate.m)
  - defines the foreign write callbacks
  - creates the custom Chez output ports
  - rebinds Scheme output/error ports during eval and load
- [examples/redirect_io_demo.ss](examples/redirect_io_demo.ss)
  - simple manual test for GUI REPL output and error routing
