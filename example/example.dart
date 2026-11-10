// Runs JavaScript in the QuickJS library this package builds, through
// dart:ffi and its C API (src/codelessly_quickjs.h).
//
// Apps don't write this: `codelessly_sdk` loads the library and runs a
// project's scripts by itself. This shows what the package contains, for
// anyone who wants to use the engine directly.
//
//   tool/build.sh                  # builds the library for this machine
//   dart run example/example.dart
//
// In a Flutter app the library is built with the app and opened with
// `DynamicLibrary.open('libcodelessly_quickjs.so')` on Android and Linux,
// and `DynamicLibrary.process()` on iOS and macOS.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:codelessly_quickjs/codelessly_quickjs.dart';

void main() {
  final String ext = Platform.isMacOS ? 'dylib' : 'so';
  final String path =
      '${Directory.current.path}/.dart_tool/codelessly_quickjs/libcodelessly_quickjs.$ext';
  if (!File(path).existsSync()) {
    stderr.writeln('Build the library first: tool/build.sh');
    exit(1);
  }
  final QuickJs js = QuickJs(DynamicLibrary.open(path));
  print('QuickJS ${js.version} (this package builds $quickJsVersion)');

  // One runtime: an isolated heap of at most 32 MB, with only the
  // ECMAScript intrinsics (no files, network, timers or processes).
  final Pointer<Void> runtime = js.create(memoryLimit: 32 << 20);
  try {
    // Evaluate global code: null when it ran.
    final String? error = js.eval(runtime, '''
      function payment(json) {
        const { principal, rate, years } = JSON.parse(json);
        const monthly = rate / 12 / 100;
        const n = years * 12;
        const value = principal * monthly / (1 - Math.pow(1 + monthly, -n));
        return JSON.stringify({ payment: Math.round(value * 100) / 100 });
      }
    ''');
    if (error != null) throw StateError(error);

    // Call a global function with one string argument. Values cross the
    // boundary as strings, so JSON carries structured data.
    final String result = js.call(
      runtime,
      'payment',
      jsonEncode({'principal': 250000, 'rate': 6.5, 'years': 30}),
    );
    print('payment: ${jsonDecode(result)['payment']}');

    // A script error is data: a JSON object after the byte 0x01.
    final String thrown = js.call(runtime, 'missing', '');
    print('error: ${jsonDecode(thrown.substring(1))['message']}');

    // A run that takes too long is stopped: "limit": "time".
    final String? slow = js.eval(runtime, 'while (true) {}', timeoutMs: 50);
    print('limit: ${jsonDecode(slow!)['limit']}');

    print('heap: ${js.memoryUsed(runtime)} bytes');
  } finally {
    js.free(runtime);
  }
}

typedef _NewC = Pointer<Void> Function(Int64, Int64);
typedef _NewD = Pointer<Void> Function(int, int);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);
typedef _EvalC =
    Pointer<Uint8> Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Int64,
      Pointer<Uint8>,
      Int64,
    );
typedef _EvalD =
    Pointer<Uint8> Function(
      Pointer<Void>,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
    );
typedef _CallC =
    Pointer<Uint8> Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Int64,
      Int64,
    );
typedef _CallD =
    Pointer<Uint8> Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      int,
      int,
    );
typedef _MemoryC = Int64 Function(Pointer<Void>);
typedef _MemoryD = int Function(Pointer<Void>);
typedef _AllocC = Pointer<Uint8> Function(Int64);
typedef _AllocD = Pointer<Uint8> Function(int);
typedef _DeallocC = Void Function(Pointer<Uint8>);
typedef _DeallocD = void Function(Pointer<Uint8>);
typedef _VersionC = Pointer<Uint8> Function();

/// The library's functions, with Dart strings in and out.
class QuickJs {
  QuickJs(DynamicLibrary lib)
    : _new = lib.lookupFunction<_NewC, _NewD>('cljs_new'),
      _free = lib.lookupFunction<_FreeC, _FreeD>('cljs_free'),
      _eval = lib.lookupFunction<_EvalC, _EvalD>('cljs_eval'),
      _call = lib.lookupFunction<_CallC, _CallD>('cljs_call'),
      _memoryUsed = lib.lookupFunction<_MemoryC, _MemoryD>('cljs_memory_used'),
      _alloc = lib.lookupFunction<_AllocC, _AllocD>('cljs_alloc'),
      _dealloc = lib.lookupFunction<_DeallocC, _DeallocD>('cljs_dealloc'),
      _freeString = lib.lookupFunction<_DeallocC, _DeallocD>(
        'cljs_free_string',
      ),
      _version = lib.lookupFunction<_VersionC, _VersionC>('cljs_version');

  final _NewD _new;
  final _FreeD _free;
  final _EvalD _eval;
  final _CallD _call;
  final _MemoryD _memoryUsed;
  final _AllocD _alloc;
  final _DeallocD _dealloc;
  final _DeallocD _freeString;
  final _VersionC _version;

  /// A runtime whose heap is limited to [memoryLimit] bytes.
  Pointer<Void> create({int memoryLimit = 32 << 20}) {
    final Pointer<Void> runtime = _new(memoryLimit, 0);
    if (runtime == nullptr) throw StateError('Could not create a runtime.');
    return runtime;
  }

  /// Frees [runtime] and everything in it.
  void free(Pointer<Void> runtime) => _free(runtime);

  /// Bytes of memory [runtime]'s heap uses now.
  int memoryUsed(Pointer<Void> runtime) => _memoryUsed(runtime);

  /// Evaluates [code] as global code. Null when it ran, else its error as
  /// JSON: `{"name", "message", "stack", "limit"?}`.
  String? eval(Pointer<Void> runtime, String code, {int timeoutMs = 1000}) {
    final (Pointer<Uint8> c, int length) = _in(code);
    final (Pointer<Uint8> file, _) = _in('example.js');
    try {
      return _out(_eval(runtime, c, length, file, timeoutMs));
    } finally {
      _dealloc(c);
      _dealloc(file);
    }
  }

  /// Calls the global function [name] with [argument] and returns its
  /// result as a string. An error is a JSON object after the byte 0x01.
  String call(
    Pointer<Void> runtime,
    String name,
    String argument, {
    int timeoutMs = 1000,
  }) {
    final (Pointer<Uint8> n, _) = _in(name);
    final (Pointer<Uint8> a, int length) = _in(argument);
    try {
      return _out(_call(runtime, n, a, length, timeoutMs)) ?? '';
    } finally {
      _dealloc(n);
      _dealloc(a);
    }
  }

  /// The QuickJS release of the library.
  String get version => _read(_version());

  /// [s] as a NUL-terminated UTF-8 string the library allocated.
  (Pointer<Uint8>, int) _in(String s) {
    final Uint8List bytes = utf8.encode(s);
    final Pointer<Uint8> p = _alloc(bytes.length + 1);
    p.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    return (p, bytes.length);
  }

  static String _read(Pointer<Uint8> p) {
    int n = 0;
    while (p[n] != 0) {
      n++;
    }
    return utf8.decode(p.asTypedList(n));
  }

  /// Reads and frees a string the library returned.
  String? _out(Pointer<Uint8> p) {
    if (p == nullptr) return null;
    final String s = _read(p);
    _freeString(p);
    return s;
  }
}
