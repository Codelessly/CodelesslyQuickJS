# codelessly_quickjs

The sandboxed JavaScript engine that runs [Codelessly](https://codelessly.com) scripts on Android, iOS, macOS and Linux. It is [QuickJS](https://bellard.org/quickjs/) 2025-04-26, with a small C API (`src/codelessly_quickjs.h`) that `codelessly_sdk` calls through `dart:ffi`.

Add it to an app whose Codelessly project uses scripts:

```sh
flutter pub add codelessly_quickjs
```

Apps without scripts don't need it and don't pay for it. It adds about 0.6 MB per ABI (arm64 is similar to x86_64's 600 KB stripped).

On the web, scripts run in a Web Worker and this package isn't used.

## The sandbox

Each runtime has only the ECMAScript intrinsics: no `std` or `os` modules, so no files, network, timers or processes. Its heap and stack are limited, and an interrupt handler stops code that runs past its time budget. `codelessly_sdk` loads a driver into each runtime before any script. The driver removes everything that isn't standard ECMAScript, freezes the intrinsics, blocks code generation and `import()`, and exposes only the host APIs a script is granted.

## Layout

- `src/quickjs/`: QuickJS sources, unmodified (MIT, see `src/quickjs/LICENSE`).
- `src/codelessly_quickjs.{c,h}`: the C API (`cljs_new`, `cljs_eval`, `cljs_call`, ...).
- `src/CMakeLists.txt`: the build for Android and Linux, and for tests on the machine (`tool/build.sh`).
- `ios/` and `macos/`: CocoaPods builds of the same sources, through forwarder files in `Classes/`.
- `test/`: tests of the C API through `dart:ffi` (`flutter test` builds the library with `tool/build.sh`, which needs CMake and a C compiler).

## License

MIT, see `LICENSE`. QuickJS is Copyright (c) 2017-2021 Fabrice Bellard and Charlie Gordon, under the MIT license in `src/quickjs/LICENSE`.
