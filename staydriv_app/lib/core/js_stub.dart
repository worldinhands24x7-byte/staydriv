// js_stub.dart
// Mock representation of dart:js context for native platforms where dart:js is unavailable.

class JsStubContext {
  const JsStubContext();

  dynamic operator [](dynamic key) => const _JsStubObject();
  void operator []=(dynamic key, dynamic value) {}

  dynamic callMethod(String method, [List? args]) => null;
}

class _JsStubObject {
  const _JsStubObject();

  dynamic operator [](dynamic key) => null;
  void operator []=(dynamic key, dynamic value) {}
  dynamic callMethod(String method, [List? args]) => null;
}

const context = JsStubContext();

Function allowInterop(Function f) => f;
