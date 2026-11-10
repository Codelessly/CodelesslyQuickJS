# codelessly_quickjs

The sandboxed JavaScript engine that runs [Codelessly](https://codelessly.com) scripts on Android, iOS, macOS and
Linux. It is [QuickJS](https://bellard.org/quickjs/) 2025-04-26 with a small C API, which
[`codelessly_sdk`](https://pub.dev/packages/codelessly_sdk) calls through `dart:ffi`.

## Do I need it?

A Codelessly project can include **scripts**: JavaScript that "Run script" actions and formulas run, for logic
that formulas and actions express badly (validation, calculations, data shaping).

| Your app | |
|---|---|
| Shows a project that uses scripts, on Android, iOS, macOS or Linux | **Add this package.** |
| Shows a project without scripts | Not needed. |
| Runs on the web | Not needed: scripts run in a Web Worker. |
| Runs on Windows | Not supported yet: scripts fail with an `EngineUnavailable` error. |

Without the package, a script fails with an `EngineUnavailable` error that says to add it. The failure is data
(the action's error chain runs); the app doesn't crash.

## Install

```sh
flutter pub add codelessly_quickjs
```

That is all. There is nothing to import or call: `codelessly_sdk` finds the native library when a script first
runs. The package is separate from the SDK so that apps without scripts don't carry the engine.

| | |
|---|---|
| Platforms | Android, iOS, macOS, Linux (an FFI plugin: the library is built with your app) |
| Size | About 0.6 MB per ABI (x86_64 is 600 KB stripped; arm64 is similar) |
| Requires | Dart 3.9, Flutter 3.32 or newer |
| Build tools | What Flutter already needs for each platform: the Android NDK, Xcode, or CMake and a C compiler on Linux |

## The sandbox

Each script runs in its own QuickJS runtime:

- **Only the ECMAScript intrinsics.** No `std` or `os` modules, so no files, network, timers or processes.
- **Limited.** The heap and the stack are capped, and an interrupt handler stops code that runs past its time
  budget. A runtime that hit a limit is thrown away.
- **Locked down by the SDK.** Before any script, `codelessly_sdk` loads a driver into the runtime that removes
  everything that isn't standard ECMAScript, freezes the intrinsics, blocks code generation and `import()`, and
  exposes only the host APIs the script was granted.

The script language and its host API are documented in the SDK's guide:
[Scripting](https://github.com/Codelessly/CodelesslySDK/blob/master/docs/guide/10-scripting.md).

## API

### Dart

The Dart library has one constant. Everything else is native.

```dart
import 'package:codelessly_quickjs/codelessly_quickjs.dart';

print(quickJsVersion); // 2025-04-26
```

### C (through `dart:ffi`)

Declared in [`src/codelessly_quickjs.h`](src/codelessly_quickjs.h). Strings cross the boundary as NUL-terminated
UTF-8, and every string the API returns must be freed with `cljs_free_string`.

| Function | |
|---|---|
| `cljs_t *cljs_new(int64_t memory_limit, int64_t stack_size)` | Creates a runtime with a heap of at most `memory_limit` bytes and a stack of `stack_size` bytes (0 keeps QuickJS's defaults). NULL when it can't be created. |
| `void cljs_free(cljs_t *s)` | Frees the runtime and everything in it. |
| `char *cljs_eval(cljs_t *s, const char *code, int64_t len, const char *filename, int64_t timeout_ms)` | Evaluates global code, then runs pending jobs. NULL on success, or a JSON error `{"name", "message", "stack", "limit"?}`. Stops after `timeout_ms` (0 for no limit) with `"limit": "time"`. |
| `char *cljs_call(cljs_t *s, const char *name, const char *arg, int64_t arg_len, int64_t timeout_ms)` | Calls the global function `name` with one string argument, then runs pending jobs (promise reactions). Returns the result as a string, or a JSON error prefixed with the byte `0x01`. |
| `int64_t cljs_memory_used(cljs_t *s)` | Bytes the runtime's heap uses now. |
| `uint8_t *cljs_alloc(int64_t n)` / `void cljs_dealloc(void *p)` | Memory for the caller to pass strings in. |
| `void cljs_free_string(char *p)` | Frees a string the API returned. |
| `const char *cljs_version(void)` | The QuickJS version. Not to be freed. |

The library is `libcodelessly_quickjs.so` on Android and Linux, and is linked into the app's process on iOS and
macOS (`DynamicLibrary.process()`, or the `codelessly_quickjs` framework).

## Example

[`example/example.dart`](example/example.dart) uses the engine directly: it creates a runtime, defines a
function, calls it with JSON, and shows an error and a time limit.

```sh
tool/build.sh                  # builds the library for this machine (CMake and a C compiler)
dart run example/example.dart
```

```
QuickJS 2025-04-26 (this package builds 2025-04-26)
payment: 1580.17
error: Missing host function
limit: time
heap: 64754 bytes
```

Apps don't write that code; the SDK does it for them.

## Repository layout

- `src/quickjs/`: QuickJS sources, unmodified (MIT, see `src/quickjs/LICENSE`).
- `src/codelessly_quickjs.{c,h}`: the C API (`cljs_new`, `cljs_eval`, `cljs_call`, ...).
- `src/CMakeLists.txt`: the build for Android and Linux, and for tests on the machine (`tool/build.sh`).
- `android/`, `linux/`: the Flutter plugin builds, which use `src/CMakeLists.txt`.
- `ios/` and `macos/`: CocoaPods builds of the same sources, through forwarder files in `Classes/`.
- `test/`: tests of the C API through `dart:ffi`.

## Developing

```sh
flutter pub get
flutter test        # builds the library with tool/build.sh, then tests the C API
```

`codelessly_sdk`'s scripting tests use the same build (`tool/build_quickjs.sh` in the SDK).

## License

MIT, see [LICENSE](LICENSE). QuickJS is Copyright (c) 2017-2021 Fabrice Bellard and Charlie Gordon, under the MIT
license in `src/quickjs/LICENSE`.
