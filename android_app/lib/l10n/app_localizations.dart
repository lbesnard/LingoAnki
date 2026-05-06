import 'package:flutter/material.dart';

/// Hand-written localizations — no code generation required.
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const delegate = _AppLocalizationsDelegate();
  static const supportedLocales = [Locale('en'), Locale('fr')];

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
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'fr'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
