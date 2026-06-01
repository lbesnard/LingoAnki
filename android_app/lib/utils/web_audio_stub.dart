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

// Mirror signatures to ensure the Android build passes cleanly
dynamic convertEndedCallback(Function callback) => null;
dynamic convertErrorCallback(Function callback) => null;
