// lib/utils/web_audio_web.dart

export 'package:web/web.dart' show HTMLAudioElement, Event;
export 'dart:js_interop' show JSFunction;

import 'dart:js_interop' as jsi;
import 'package:web/web.dart';

// Provide explicit top-level wrappers that preserve strict static function signatures
jsi.JSFunction convertEndedCallback(void Function(Event) callback) =>
    callback.toJS;
jsi.JSFunction convertErrorCallback(void Function(Event) callback) =>
    callback.toJS;
