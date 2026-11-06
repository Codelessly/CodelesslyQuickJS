// Tests of the C API (src/codelessly_quickjs.h) through dart:ffi, on a
// build of the library for this machine (tool/build.sh).
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:codelessly_quickjs/codelessly_quickjs.dart';
import 'package:flutter_test/flutter_test.dart';

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
typedef _AllocC = Pointer<Uint8> Function(Int64);
typedef _AllocD = Pointer<Uint8> Function(int);
typedef _DeallocC = Void Function(Pointer<Uint8>);
typedef _DeallocD = void Function(Pointer<Uint8>);
typedef _VersionC = Pointer<Uint8> Function();

/// The library's functions, with UTF-8 strings in and out.
class _Engine {
  _Engine(DynamicLibrary lib)
    : _new = lib.lookupFunction<_NewC, _NewD>('cljs_new'),
      free = lib.lookupFunction<_FreeC, _FreeD>('cljs_free'),
      _eval = lib.lookupFunction<_EvalC, _EvalD>('cljs_eval'),
      _call = lib.lookupFunction<_CallC, _CallD>('cljs_call'),
      _alloc = lib.lookupFunction<_AllocC, _AllocD>('cljs_alloc'),
      _dealloc = lib.lookupFunction<_DeallocC, _DeallocD>('cljs_dealloc'),
      _freeString = lib.lookupFunction<_DeallocC, _DeallocD>(
        'cljs_free_string',
      ),
      _version = lib.lookupFunction<_VersionC, _VersionC>('cljs_version');

  final _NewD _new;
  final _FreeD free;
  final _EvalD _eval;
  final _CallD _call;
  final _AllocD _alloc;
  final _DeallocD _dealloc;
  final _DeallocD _freeString;
  final _VersionC _version;

  Pointer<Void> create({int memoryLimit = 32 << 20}) => _new(memoryLimit, 0);

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

  String? _out(Pointer<Uint8> p) {
    if (p == nullptr) return null;
    final String s = _read(p);
    _freeString(p);
    return s;
  }

  /// Null when [code] ran, else its error as JSON.
  String? eval(Pointer<Void> rt, String code, {int timeoutMs = 1000}) {
    final (Pointer<Uint8> c, int len) = _in(code);
    final (Pointer<Uint8> f, _) = _in('test.js');
    try {
      return _out(_eval(rt, c, len, f, timeoutMs));
    } finally {
      _dealloc(c);
      _dealloc(f);
    }
  }

  /// The global function [name]'s result for [arg]; an error starts with
  /// the byte 0x01.
  String? call(
    Pointer<Void> rt,
    String name,
    String arg, {
    int timeoutMs = 1000,
  }) {
    final (Pointer<Uint8> n, _) = _in(name);
    final (Pointer<Uint8> a, int len) = _in(arg);
    try {
      return _out(_call(rt, n, a, len, timeoutMs));
    } finally {
      _dealloc(n);
      _dealloc(a);
    }
  }

  String get version => _read(_version());
}

late final _Engine _engine;

void main() {
  setUpAll(() {
    final String ext = Platform.isMacOS ? 'dylib' : 'so';
    final String path =
        '${Directory.current.path}/.dart_tool/codelessly_quickjs/libcodelessly_quickjs.$ext';
    if (!File(path).existsSync()) {
      final ProcessResult r = Process.runSync('bash', ['tool/build.sh']);
      if (r.exitCode != 0) {
        fail('Could not build the library:\n${r.stdout}\n${r.stderr}');
      }
    }
    _engine = _Engine(DynamicLibrary.open(path));
  });

  test('reports the QuickJS release it builds', () {
    expect(_engine.version, quickJsVersion);
  });

  test('evaluates code and calls functions with strings', () {
    final Pointer<Void> rt = _engine.create();
    addTearDown(() => _engine.free(rt));
    expect(
      _engine.eval(
        rt,
        'globalThis.twice = (s) => JSON.stringify(Number(s) * 2);',
      ),
      isNull,
    );
    expect(_engine.call(rt, 'twice', '21'), '42');
  });

  test('a syntax error comes back as JSON', () {
    final Pointer<Void> rt = _engine.create();
    addTearDown(() => _engine.free(rt));
    final Map<String, dynamic> error = jsonDecode(_engine.eval(rt, 'let = ;')!);
    expect(error['name'], 'SyntaxError');
  });

  test('code past its time budget stops with a time limit', () {
    final Pointer<Void> rt = _engine.create();
    addTearDown(() => _engine.free(rt));
    final Stopwatch watch = Stopwatch()..start();
    final Map<String, dynamic> error = jsonDecode(
      _engine.eval(rt, 'while (true) {}', timeoutMs: 100)!,
    );
    expect(error['limit'], 'time');
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });

  test('a runtime past its memory limit fails without crashing', () {
    final Pointer<Void> rt = _engine.create(memoryLimit: 4 << 20);
    addTearDown(() => _engine.free(rt));
    final String? error = _engine.eval(
      rt,
      'const a = []; while (true) a.push(new Array(10000).fill(1));',
    );
    expect(error, isNotNull);
    expect(error, contains('memory'));
  });

  test('no std or os modules, files, network or timers', () {
    final Pointer<Void> rt = _engine.create();
    addTearDown(() => _engine.free(rt));
    expect(
      _engine.eval(
        rt,
        'globalThis.reach = () => JSON.stringify(["std", "os", "fetch", "setTimeout", "XMLHttpRequest", "require"].filter((n) => typeof globalThis[n] !== "undefined"));',
      ),
      isNull,
    );
    expect(_engine.call(rt, 'reach', ''), '[]');
  });
}
