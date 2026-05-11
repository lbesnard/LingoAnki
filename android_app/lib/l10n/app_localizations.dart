import 'package:flutter/material.dart';

/// Hand-written localizations — no code generation required.
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const delegate = _AppLocalizationsDelegate();
  static const supportedLocales = [Locale('en'), Locale('fr'), Locale('es')];

  String _t(String key) =>
      (_strings[locale.languageCode] ?? _strings['en']!)[key] ??
      _strings['en']![key] ??
      key;

  String get appTitle => _t('appTitle');
  String get navDiary => _t('navDiary');
  String get navLessons => _t('navLessons');
  String get navSettings => _t('navSettings');
  String get cancelButton => _t('cancelButton');
  String get syncAll => _t('syncAll');
  String get syncInProgress => _t('syncInProgress');
  String get syncCancelled => _t('syncCancelled');
  String syncFailed(String error) => _t('syncFailed').replaceAll('{error}', error);
  String syncedFiles(int count) => _t('syncedFiles').replaceAll('{count}', '$count');
  String get noLessons => _t('noLessons');
  String get serverUnreachable => _t('serverUnreachable');
  String get syncThisLesson => _t('syncThisLesson');
  String get lessonSynced => _t('lessonSynced');
  String get audioNotSynced => _t('audioNotSynced');
  String get noContent => _t('noContent');
  String get noDateInLesson => _t('noDateInLesson');
  String noDiaryEntry(String date) => _t('noDiaryEntry').replaceAll('{date}', date);
  String get loopOn => _t('loopOn');
  String get loopOff => _t('loopOff');
  String fontSizeTooltip(String size) => _t('fontSizeTooltip').replaceAll('{size}', size);
  String get loginServerUrl => _t('loginServerUrl');
  String get loginServerHint => _t('loginServerHint');
  String get loginServerRequired => _t('loginServerRequired');
  String get loginUsername => _t('loginUsername');
  String get loginUsernameRequired => _t('loginUsernameRequired');
  String get loginPassword => _t('loginPassword');
  String get loginPasswordRequired => _t('loginPasswordRequired');
  String get loginButton => _t('loginButton');
  String get settingsTitle => _t('settingsTitle');
  String get settingsAccount => _t('settingsAccount');
  String get settingsUsernameLabel => _t('settingsUsernameLabel');
  String get settingsServerLabel => _t('settingsServerLabel');
  String get settingsChangeServer => _t('settingsChangeServer');
  String get settingsSave => _t('settingsSave');
  String get settingsServerUpdated => _t('settingsServerUpdated');
  String get settingsSession => _t('settingsSession');
  String get settingsSignOut => _t('settingsSignOut');
  String get settingsSignOutSubtitle => _t('settingsSignOutSubtitle');
  String get settingsSignOutTitle => _t('settingsSignOutTitle');
  String get settingsSignOutBody => _t('settingsSignOutBody');
  String get settingsData => _t('settingsData');
  String get settingsStorageLabel => _t('settingsStorageLabel');
  String get settingsClearData => _t('settingsClearData');
  String get settingsClearDataSubtitle => _t('settingsClearDataSubtitle');
  String get settingsClearDataTitle => _t('settingsClearDataTitle');
  String get settingsClearDataBody => _t('settingsClearDataBody');
  String get settingsClearButton => _t('settingsClearButton');
  String get settingsDataCleared => _t('settingsDataCleared');
  String settingsErrorClearing(String error) => _t('settingsErrorClearing').replaceAll('{error}', error);

  // Onboarding
  String get homeWelcomeTitle => _t('homeWelcomeTitle');
  String get homeWelcomeBody => _t('homeWelcomeBody');
  String get homeWelcomeTip => _t('homeWelcomeTip');
  String get homeGoDiary => _t('homeGoDiary');

  // Help dialog
  String get helpTitle => _t('helpTitle');
  String get helpBody => _t('helpBody');
  String get helpClose => _t('helpClose');

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'appTitle': 'LingoDiary',
      'navDiary': 'Diary',
      'navLessons': 'Lessons',
      'navSettings': 'Settings',
      'cancelButton': 'Cancel',
      'syncAll': 'Sync All',
      'syncInProgress': 'Sync in progress\u2026',
      'syncCancelled': 'Cancelled.',
      'syncFailed': 'Sync failed: {error}',
      'syncedFiles': 'Synced {count} file(s) \u2713',
      'noLessons': 'No lessons yet.\nTap Sync All to download.',
      'serverUnreachable': 'Server unreachable \u2014 showing cached lessons',
      'syncThisLesson': 'Sync this lesson',
      'lessonSynced': 'Synced',
      'audioNotSynced': 'Audio not synced yet \u2014 tap \u27f3 in the toolbar.',
      'noContent': 'No content \u2014 tap Sync to download.',
      'noDateInLesson': 'No date found in lesson name.',
      'noDiaryEntry': 'No diary entry found for {date}.\nMake sure the server has this entry.',
      'loopOn': 'Loop: on',
      'loopOff': 'Loop: off',
      'fontSizeTooltip': 'Font size ({size})',
      'loginServerUrl': 'Server URL',
      'loginServerHint': 'http://192.168.1.x:8084',
      'loginServerRequired': 'Enter the server URL',
      'loginUsername': 'Username',
      'loginUsernameRequired': 'Enter username',
      'loginPassword': 'Password',
      'loginPasswordRequired': 'Enter password',
      'loginButton': 'Login',
      'settingsTitle': 'Settings',
      'settingsAccount': 'Account',
      'settingsUsernameLabel': 'Username',
      'settingsServerLabel': 'Server',
      'settingsChangeServer': 'Change server URL',
      'settingsSave': 'Save',
      'settingsServerUpdated': 'Server URL updated',
      'settingsSession': 'Session',
      'settingsSignOut': 'Sign out',
      'settingsSignOutSubtitle': 'Keeps all cached data on this device',
      'settingsSignOutTitle': 'Sign out',
      'settingsSignOutBody': 'Your locally cached lessons and diary data will be kept.\n\nSign out?',
      'settingsData': 'Data',
      'settingsStorageLabel': 'Cache size',
      'settingsClearData': 'Clear all cached data',
      'settingsClearDataSubtitle': 'Deletes downloaded lessons & diary cache from this device',
      'settingsClearDataTitle': 'Clear all cached data',
      'settingsClearDataBody': 'This will delete all downloaded lesson files (audio + text) and the local database cache.\n\nYou will remain signed in and can sync again from the server.\n\nThis cannot be undone. Continue?',
      'settingsClearButton': 'Clear',
      'settingsDataCleared': 'All cached data cleared.',
      'settingsErrorClearing': 'Error clearing data: {error}',
      // Onboarding
      'homeWelcomeTitle': 'Get started',
      'homeWelcomeBody': 'Write a few sentences about your day, then hit Generate Lessons. The app translates them and creates audio lessons in TPRS style.',
      'homeWelcomeTip': 'Tip: simple sentences work best. "I went to the market. I bought bread." The app does the rest.',
      'homeGoDiary': 'Write your first diary entry \u2192',
      // Help
      'helpTitle': 'How it works',
      'helpBody': '1. Go to Diary and write a few sentences about your day in your native language.\n\n2. Tap Generate Lessons. The server translates each sentence and records audio with Q\u0026A.\n\n3. Open Lessons and listen. Each sentence is highlighted as it plays. Tap any sentence to reveal the translation.\n\n4. Score yourself at the end of each lesson to track your mastery over time.',
      'helpClose': 'Got it',
    },
    'fr': {
      'appTitle': 'LingoDiary',
      'navDiary': 'Journal',
      'navLessons': 'Le\u00e7ons',
      'navSettings': 'Param\u00e8tres',
      'cancelButton': 'Annuler',
      'syncAll': 'Tout synchroniser',
      'syncInProgress': 'Synchronisation en cours\u2026',
      'syncCancelled': 'Annul\u00e9.',
      'syncFailed': '\u00c9chec de la sync\u00a0: {error}',
      'syncedFiles': '{count} fichier(s) synchronis\u00e9(s) \u2713',
      'noLessons': 'Aucune le\u00e7on.\nAppuyez sur \u00ab\u00a0Tout synchroniser\u00a0\u00bb.',
      'serverUnreachable': 'Serveur inaccessible \u2014 affichage du cache',
      'syncThisLesson': 'Synchroniser cette le\u00e7on',
      'lessonSynced': 'Synchronis\u00e9',
      'audioNotSynced': 'Audio non synchronis\u00e9 \u2014 appuyez sur \u27f3 dans la barre.',
      'noContent': 'Aucun contenu \u2014 appuyez sur Sync pour t\u00e9l\u00e9charger.',
      'noDateInLesson': 'Aucune date trouv\u00e9e dans le nom de la le\u00e7on.',
      'noDiaryEntry': 'Aucune entr\u00e9e de journal pour {date}.\nV\u00e9rifiez que le serveur contient cette entr\u00e9e.',
      'loopOn': 'Boucle\u00a0: activ\u00e9e',
      'loopOff': 'Boucle\u00a0: d\u00e9sactiv\u00e9e',
      'fontSizeTooltip': 'Taille police ({size})',
      'loginServerUrl': 'URL du serveur',
      'loginServerHint': 'http://192.168.1.x:8084',
      'loginServerRequired': "Entrez l'URL du serveur",
      'loginUsername': "Nom d'utilisateur",
      'loginUsernameRequired': "Entrez le nom d'utilisateur",
      'loginPassword': 'Mot de passe',
      'loginPasswordRequired': 'Entrez le mot de passe',
      'loginButton': 'Connexion',
      'settingsTitle': 'Param\u00e8tres',
      'settingsAccount': 'Compte',
      'settingsUsernameLabel': "Nom d'utilisateur",
      'settingsServerLabel': 'Serveur',
      'settingsChangeServer': "Modifier l'URL du serveur",
      'settingsSave': 'Enregistrer',
      'settingsServerUpdated': 'URL du serveur mise \u00e0 jour',
      'settingsSession': 'Session',
      'settingsSignOut': 'Se d\u00e9connecter',
      'settingsSignOutSubtitle': 'Conserve toutes les donn\u00e9es en cache',
      'settingsSignOutTitle': 'Se d\u00e9connecter',
      'settingsSignOutBody': 'Vos le\u00e7ons et journal en cache seront conserv\u00e9s.\n\nSe d\u00e9connecter\u00a0?',
      'settingsData': 'Donn\u00e9es',
      'settingsStorageLabel': 'Taille du cache',
      'settingsClearData': 'Effacer toutes les donn\u00e9es',
      'settingsClearDataSubtitle': 'Supprime les le\u00e7ons et le cache du journal',
      'settingsClearDataTitle': 'Effacer toutes les donn\u00e9es',
      'settingsClearDataBody': 'Cela supprimera tous les fichiers de le\u00e7ons t\u00e9l\u00e9charg\u00e9s (audio + texte) et le cache de la base de donn\u00e9es locale.\n\nVous resterez connect\u00e9 et pourrez re-synchroniser depuis le serveur.\n\nCette action est irr\u00e9versible. Continuer\u00a0?',
      'settingsClearButton': 'Effacer',
      'settingsDataCleared': 'Toutes les donn\u00e9es en cache ont \u00e9t\u00e9 effac\u00e9es.',
      'settingsErrorClearing': 'Erreur lors de la suppression\u00a0: {error}',
      // Onboarding
      'homeWelcomeTitle': 'Commencer',
      'homeWelcomeBody': '\u00c9crivez quelques phrases sur votre journ\u00e9e, puis appuyez sur G\u00e9n\u00e9rer des le\u00e7ons. L\u2019application les traduit et cr\u00e9e des le\u00e7ons audio en style TPRS.',
      'homeWelcomeTip': 'Astuce\u00a0: les phrases simples fonctionnent le mieux. \u00ab\u00a0Je suis all\u00e9 au march\u00e9. J\u2019ai achet\u00e9 du pain.\u00a0\u00bb L\u2019application fait le reste.',
      'homeGoDiary': '\u00c9crire ma premi\u00e8re entr\u00e9e \u2192',
      // Help
      'helpTitle': 'Comment \u00e7a marche',
      'helpBody': '1. Allez dans Journal et \u00e9crivez quelques phrases sur votre journ\u00e9e dans votre langue maternelle.\n\n2. Appuyez sur G\u00e9n\u00e9rer des le\u00e7ons. Le serveur traduit chaque phrase et enregistre l\u2019audio avec des questions-r\u00e9ponses.\n\n3. Ouvrez Le\u00e7ons et \u00e9coutez. Chaque phrase est mise en \u00e9vidence pendant la lecture. Appuyez sur une phrase pour r\u00e9v\u00e9ler la traduction.\n\n4. Notez-vous \u00e0 la fin de chaque le\u00e7on pour suivre votre progression.',
      'helpClose': 'Compris',
    },
    'es': {
      'appTitle': 'LingoDiary',
      'navDiary': 'Diario',
      'navLessons': 'Lecciones',
      'navSettings': 'Ajustes',
      'cancelButton': 'Cancelar',
      'syncAll': 'Sincronizar todo',
      'syncInProgress': 'Sincronizando\u2026',
      'syncCancelled': 'Cancelado.',
      'syncFailed': 'Error de sincronizaci\u00f3n: {error}',
      'syncedFiles': '{count} archivo(s) sincronizado(s) \u2713',
      'noLessons': 'Sin lecciones todav\u00eda.\nPulsa Sincronizar todo para descargar.',
      'serverUnreachable': 'Servidor no disponible \u2014 mostrando cach\u00e9',
      'syncThisLesson': 'Sincronizar esta lecci\u00f3n',
      'lessonSynced': 'Sincronizado',
      'audioNotSynced': 'Audio no sincronizado \u2014 pulsa \u27f3 en la barra.',
      'noContent': 'Sin contenido \u2014 pulsa Sincronizar para descargar.',
      'noDateInLesson': 'No se encontr\u00f3 fecha en el nombre de la lecci\u00f3n.',
      'noDiaryEntry': 'No se encontr\u00f3 entrada de diario para {date}.\nAseg\u00farate de que el servidor tenga esta entrada.',
      'loopOn': 'Bucle: activado',
      'loopOff': 'Bucle: desactivado',
      'fontSizeTooltip': 'Tama\u00f1o de fuente ({size})',
      'loginServerUrl': 'URL del servidor',
      'loginServerHint': 'http://192.168.1.x:8084',
      'loginServerRequired': 'Introduce la URL del servidor',
      'loginUsername': 'Usuario',
      'loginUsernameRequired': 'Introduce el nombre de usuario',
      'loginPassword': 'Contrase\u00f1a',
      'loginPasswordRequired': 'Introduce la contrase\u00f1a',
      'loginButton': 'Iniciar sesi\u00f3n',
      'settingsTitle': 'Ajustes',
      'settingsAccount': 'Cuenta',
      'settingsUsernameLabel': 'Usuario',
      'settingsServerLabel': 'Servidor',
      'settingsChangeServer': 'Cambiar URL del servidor',
      'settingsSave': 'Guardar',
      'settingsServerUpdated': 'URL del servidor actualizada',
      'settingsSession': 'Sesi\u00f3n',
      'settingsSignOut': 'Cerrar sesi\u00f3n',
      'settingsSignOutSubtitle': 'Conserva todos los datos en cach\u00e9',
      'settingsSignOutTitle': 'Cerrar sesi\u00f3n',
      'settingsSignOutBody': 'Tus lecciones y diario en cach\u00e9 se conservar\u00e1n.\n\n\u00bfCerrar sesi\u00f3n?',
      'settingsData': 'Datos',
      'settingsStorageLabel': 'Tama\u00f1o de cach\u00e9',
      'settingsClearData': 'Borrar todos los datos',
      'settingsClearDataSubtitle': 'Elimina lecciones descargadas y cach\u00e9 del diario',
      'settingsClearDataTitle': 'Borrar todos los datos',
      'settingsClearDataBody': 'Esto eliminar\u00e1 todos los archivos de lecci\u00f3n descargados (audio + texto) y la cach\u00e9 de la base de datos local.\n\nPermanecer\u00e1s conectado y podr\u00e1s volver a sincronizar desde el servidor.\n\nEsta acci\u00f3n no se puede deshacer. \u00bfContinuar?',
      'settingsClearButton': 'Borrar',
      'settingsDataCleared': 'Todos los datos en cach\u00e9 han sido borrados.',
      'settingsErrorClearing': 'Error al borrar datos: {error}',
      // Onboarding
      'homeWelcomeTitle': 'Empezar',
      'homeWelcomeBody': 'Escribe algunas frases sobre tu d\u00eda y pulsa Generar lecciones. La app las traduce y crea lecciones de audio en estilo TPRS.',
      'homeWelcomeTip': 'Consejo: las frases simples funcionan mejor. \u00abFui al mercado. Compr\u00e9 pan.\u00bb La app hace el resto.',
      'homeGoDiary': 'Escribe tu primera entrada \u2192',
      // Help
      'helpTitle': 'C\u00f3mo funciona',
      'helpBody': '1. Ve a Diario y escribe algunas frases sobre tu d\u00eda en tu idioma nativo.\n\n2. Pulsa Generar lecciones. El servidor traduce cada frase y graba el audio con preguntas y respuestas.\n\n3. Abre Lecciones y escucha. Cada frase se resalta mientras se reproduce. Pulsa una frase para ver la traducci\u00f3n.\n\n4. Punt\u00faate al final de cada lecci\u00f3n para seguir tu progreso.',
      'helpClose': 'Entendido',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'fr', 'es'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
