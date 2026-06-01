// lib/utils/web_audio_stub.dart

class HTMLAudioElement {
  set preload(String value) {}
  set src(String value) {}
  void play() {}
  void pause() {}
  void removeAttribute(String name) {}
  dynamic get error => null;
  void addEventListener(String type, dynamic callback) {}
  void removeEventListener(String type, dynamic callback) {}
}

class Event {}

// Define a stub extension so .toJS can still syntactically compile on mobile
extension StubToJS on Function {
  dynamic get toJS => null;
}
