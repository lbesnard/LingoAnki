// Selects the correct LocalDbService implementation at compile time.
// dart.library.io  → mobile/desktop (sqflite)
// dart.library.html → web (in-memory / SharedPreferences)
export 'db_stub.dart'
    if (dart.library.io) 'db_mobile.dart'
    if (dart.library.html) 'db_web.dart';
