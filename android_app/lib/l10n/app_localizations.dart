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
  String noDiarySentence(String date) => _t('noDiarySentence').replaceAll('{date}', date);
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

  // Shared UI
  String get retryButton => _t('retryButton');
  String get refreshButton => _t('refreshButton');
  String get addButton => _t('addButton');
  String get changeButton => _t('changeButton');
  String get editTooltip => _t('editTooltip');
  String get removeTooltip => _t('removeTooltip');
  String get confirmTooltip => _t('confirmTooltip');
  String get stopButton => _t('stopButton');
  String get playAllButton => _t('playAllButton');
  String get skipButton => _t('skipButton');
  String get refreshTooltip => _t('refreshTooltip');
  String get helpTooltip => _t('helpTooltip');
  String get settingsTooltip => _t('settingsTooltip');

  // Nav
  String get navHome => _t('navHome');
  String get navReview => _t('navReview');
  String get navReviewLessons => _t('navReviewLessons');
  String get translationExercise => _t('translationExercise');

  // Connection
  String get serverOnline => _t('serverOnline');
  String get serverOffline => _t('serverOffline');
  String get serverUnreachableNoCache => _t('serverUnreachableNoCache');

  // Diary
  String get diaryDate => _t('diaryDate');
  String diarySentencesFor(String date) => _t('diarySentencesFor').replaceAll('{date}', date);
  String get diaryTypeSentenceHint => _t('diaryTypeSentenceHint');
  String get diaryNoSentences => _t('diaryNoSentences');
  String get diarySaveToServer => _t('diarySaveToServer');
  String get diaryGenerateLessons => _t('diaryGenerateLessons');
  String get diaryGenerationStarting => _t('diaryGenerationStarting');
  String get diaryAddSentenceFirst => _t('diaryAddSentenceFirst');
  String diaryEntrySaved(String date, int count) => _t('diaryEntrySaved').replaceAll('{date}', date).replaceAll('{count}', '$count');
  String diarySavedLocally(String error) => _t('diarySavedLocally').replaceAll('{error}', error);
  String get diaryCouldNotConnect => _t('diaryCouldNotConnect');

  // Login
  String loginConnectionError(String error) => _t('loginConnectionError').replaceAll('{error}', error);

  // Home
  String get homeProgress => _t('homeProgress');
  String get homeMastered => _t('homeMastered');
  String get homeInProgress => _t('homeInProgress');
  String homeNewTotalEntries(int newCount, int total) => _t('homeNewTotalEntries').replaceAll('{newCount}', '$newCount').replaceAll('{total}', '$total');
  String get homeStudyNow => _t('homeStudyNow');
  String get reviewOptionsTooltip => _t('reviewOptionsTooltip');
  String get originalReview => _t('originalReview');
  String get dueForReview => _t('dueForReview');
  String get newLesson => _t('newLesson');
  String get homeRecentlyStudied => _t('homeRecentlyStudied');
  String get homeNoLessonsStudied => _t('homeNoLessonsStudied');
  String get timeAgoJustNow => _t('timeAgoJustNow');
  String timeAgoDays(int count) => _t('timeAgoDays').replaceAll('{count}', '$count');
  String timeAgoHours(int count) => _t('timeAgoHours').replaceAll('{count}', '$count');
  String timeAgoMinutes(int count) => _t('timeAgoMinutes').replaceAll('{count}', '$count');

  // Lessons
  String lessonsMasteredCount(int mastered, int total) => _t('lessonsMasteredCount').replaceAll('{mastered}', '$mastered').replaceAll('{total}', '$total');

  // Review (sentences_screen / native_first_sentences_screen)
  String get sentenceReviewTitle => _t('sentenceReviewTitle');
  String get translationExerciseTitle => _t('translationExerciseTitle');
  String get syncAudioTooltip => _t('syncAudioTooltip');
  String get syncCurrentSentence => _t('syncCurrentSentence');
  String syncAllSentencesCount(int count) => _t('syncAllSentencesCount').replaceAll('{count}', '$count');
  String get statsAndStreakTooltip => _t('statsAndStreakTooltip');
  String reviewRemaining(int count) => _t('reviewRemaining').replaceAll('{count}', '$count');
  String get offlineShowingCached => _t('offlineShowingCached');
  String get offlineLoadNewSentences => _t('offlineLoadNewSentences');
  String get downloadingAudio => _t('downloadingAudio');
  String get audioUnavailable => _t('audioUnavailable');
  String get audioSynced => _t('audioSynced');
  String syncedAudioCount(int count) => _t('syncedAudioCount').replaceAll('{count}', '$count');
  String get allCaughtUp => _t('allCaughtUp');
  String get noSentencesDue => _t('noSentencesDue');
  String get showTranslation => _t('showTranslation');
  String get hideTranslation => _t('hideTranslation');
  String showQa(int count) => _t('showQa').replaceAll('{count}', '$count');
  String get hideQa => _t('hideQa');
  String get howWellDidYouRemember => _t('howWellDidYouRemember');
  String get scoreAgain => _t('scoreAgain');
  String get scoreHard => _t('scoreHard');
  String get scoreGood => _t('scoreGood');
  String get scoreEasy => _t('scoreEasy');
  String get scoreSavedWillSync => _t('scoreSavedWillSync');
  String scoreSavedLocallyError(String error) => _t('scoreSavedLocallyError').replaceAll('{error}', error);
  String get translationAttemptHintWithEnter => _t('translationAttemptHintWithEnter');
  String get translationAttemptLabel => _t('translationAttemptLabel');
  String get fontSizeSmall => _t('fontSizeSmall');
  String get fontSizeNormal => _t('fontSizeNormal');
  String get fontSizeLarge => _t('fontSizeLarge');
  String get fontSizeExtraLarge => _t('fontSizeExtraLarge');

  // Player
  String get cycleVariantsOn => _t('cycleVariantsOn');
  String get cycleVariantsOff => _t('cycleVariantsOff');
  String get previousBlock => _t('previousBlock');
  String get nextBlock => _t('nextBlock');
  String get repeatCurrentBlock => _t('repeatCurrentBlock');
  String get stopBlockRepeat => _t('stopBlockRepeat');
  String get audioNotDownloadedYet => _t('audioNotDownloadedYet');
  String get audioNotDownloaded => _t('audioNotDownloaded');
  String get downloadingAudioWait => _t('downloadingAudioWait');
  String get contentNotAvailable => _t('contentNotAvailable');
  String get noDiaryEntriesFound => _t('noDiaryEntriesFound');
  String couldNotLoadDiaryEntry(String error) => _t('couldNotLoadDiaryEntry').replaceAll('{error}', error);
  String markedScore(String score) => _t('markedScore').replaceAll('{score}', score);
  String markedScoreWithInterval(String score, int days) => _t('markedScoreWithInterval').replaceAll('{score}', score).replaceAll('{days}', '$days');

  // Settings (new)
  String get settingsLessonPlayback => _t('settingsLessonPlayback');
  String get settingsAutoRepeatLesson => _t('settingsAutoRepeatLesson');
  String get settingsAutoRepeatLessonSubtitle => _t('settingsAutoRepeatLessonSubtitle');
  String get settingsAutoCycleVariants => _t('settingsAutoCycleVariants');
  String get settingsAutoCycleVariantsSubtitle => _t('settingsAutoCycleVariantsSubtitle');
  String get settingsMaintenance => _t('settingsMaintenance');
  String get settingsFixEverything => _t('settingsFixEverything');
  String get settingsFixEverythingSubtitle => _t('settingsFixEverythingSubtitle');
  String get settingsFillQaTranslations => _t('settingsFillQaTranslations');
  String get settingsFillQaTranslationsSubtitle => _t('settingsFillQaTranslationsSubtitle');
  String get settingsRebuildAudioTiming => _t('settingsRebuildAudioTiming');
  String get settingsRebuildAudioTimingSubtitle => _t('settingsRebuildAudioTimingSubtitle');
  String get settingsForceAudioRegen => _t('settingsForceAudioRegen');
  String get settingsForceAudioRegenSubtitle => _t('settingsForceAudioRegenSubtitle');
  String get settingsJobStarted => _t('settingsJobStarted');
  String settingsJobError(String error) => _t('settingsJobError').replaceAll('{error}', error);

  // Stats
  String get statsTitle => _t('statsTitle');
  String get dayStreak => _t('dayStreak');
  String reviewedToday(int count) => _t('reviewedToday').replaceAll('{count}', '$count');
  String get noReviewsToday => _t('noReviewsToday');
  String get statsOverview => _t('statsOverview');
  String get statsTotalReviews => _t('statsTotalReviews');
  String get statsReviewedTodayLabel => _t('statsReviewedTodayLabel');
  String get statsNoScores => _t('statsNoScores');
  String get statsScoreDistribution => _t('statsScoreDistribution');

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
      'noDiarySentence': 'No diary entry found for {date}.\nMake sure the server has this entry.',
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
      'retryButton': 'Retry',
      'refreshButton': 'Refresh',
      'addButton': 'Add',
      'changeButton': 'Change',
      'editTooltip': 'Edit',
      'removeTooltip': 'Remove',
      'confirmTooltip': 'Confirm',
      'stopButton': 'Stop',
      'playAllButton': 'Play all',
      'skipButton': 'Skip',
      'refreshTooltip': 'Refresh',
      'helpTooltip': 'Help',
      'settingsTooltip': 'Settings',
      'navHome': 'Home',
      'navReview': 'Review',
      'navReviewLessons': 'Review Lessons',
      'translationExercise': 'Translation Exercise',
      'serverOnline': 'Server online',
      'serverOffline': 'Server offline',
      'serverUnreachableNoCache': 'Server unreachable — no cached data.',
      'diaryDate': 'Diary date',
      'diarySentencesFor': 'Sentences for {date}',
      'diaryTypeSentenceHint': 'Type a sentence…',
      'diaryNoSentences': 'No sentences yet.',
      'diarySaveToServer': 'Save to Server',
      'diaryGenerateLessons': 'Generate Lessons',
      'diaryGenerationStarting': 'Starting generation…',
      'diaryAddSentenceFirst': 'Add at least one sentence first.',
      'diaryEntrySaved': '✓ Entry saved for {date} ({count} sentence(s))',
      'diarySavedLocally': 'Saved locally. Will sync on next connection.\n{error}',
      'diaryCouldNotConnect': 'Could not connect to server.',
      'loginConnectionError': 'Error: {error}\n\nCheck the server URL is correct and the server is reachable.',
      'homeProgress': 'Progress',
      'homeMastered': 'Mastered',
      'homeInProgress': 'In progress',
      'homeNewTotalEntries': '{newCount} new • {total} total entries',
      'homeStudyNow': 'Study Now',
      'reviewOptionsTooltip': 'Review options',
      'originalReview': 'Original Review',
      'dueForReview': 'Due for review',
      'newLesson': 'New lesson',
      'homeRecentlyStudied': 'Recently Studied',
      'homeNoLessonsStudied': 'No lessons studied yet.',
      'timeAgoJustNow': 'Just now',
      'timeAgoDays': '{count}d ago',
      'timeAgoHours': '{count}h ago',
      'timeAgoMinutes': '{count}m ago',
      'lessonsMasteredCount': '{mastered}/{total} mastered',
      'sentenceReviewTitle': 'Sentence Review',
      'translationExerciseTitle': 'Translation Exercise',
      'syncAudioTooltip': 'Sync audio',
      'syncCurrentSentence': 'Sync current sentence',
      'syncAllSentencesCount': 'Sync all ({count} sentences)',
      'statsAndStreakTooltip': 'Stats & Streak',
      'reviewRemaining': '{count} left',
      'offlineShowingCached': 'Offline — showing cached review. Scores will sync when connected.',
      'offlineLoadNewSentences': 'Offline — sync the app when connected to load new sentences.',
      'downloadingAudio': 'Downloading audio…',
      'audioUnavailable': 'Audio unavailable',
      'audioSynced': 'Audio synced',
      'syncedAudioCount': 'Synced audio for {count} sentences',
      'allCaughtUp': 'All caught up!',
      'noSentencesDue': 'No sentences due for review right now.',
      'showTranslation': 'Show translation',
      'hideTranslation': 'Hide translation',
      'showQa': 'Show Q&A ({count} pairs)',
      'hideQa': 'Hide Q&A',
      'howWellDidYouRemember': 'How well did you remember?',
      'scoreAgain': 'Again',
      'scoreHard': 'Hard',
      'scoreGood': 'Good',
      'scoreEasy': 'Easy',
      'scoreSavedWillSync': 'Score saved (will sync when online)',
      'scoreSavedLocallyError': 'Score saved locally — sync error: {error}',
      'translationAttemptHintWithEnter': 'Your translation attempt (press Enter to reveal)',
      'translationAttemptLabel': 'Your translation attempt',
      'fontSizeSmall': 'Small',
      'fontSizeNormal': 'Normal',
      'fontSizeLarge': 'Large',
      'fontSizeExtraLarge': 'Extra Large',
      'cycleVariantsOn': 'Cycle variants: on',
      'cycleVariantsOff': 'Cycle variants: off',
      'previousBlock': 'Previous block',
      'nextBlock': 'Next block',
      'repeatCurrentBlock': 'Repeat current block',
      'stopBlockRepeat': 'Stop block repeat',
      'audioNotDownloadedYet': '⏳ Audio not downloaded yet — syncing now, please wait…',
      'audioNotDownloaded': 'Audio not downloaded — tap ▶ or sync ⟳ to download',
      'downloadingAudioWait': 'Downloading audio… please wait',
      'contentNotAvailable': 'Content not available.\nSync the lesson to view it offline.',
      'noDiaryEntriesFound': '(No diary entries found)',
      'couldNotLoadDiaryEntry': 'Could not load diary entry.\nTap sync or check server connection.\n\nError: {error}',
      'markedScore': 'Marked {score}',
      'markedScoreWithInterval': 'Marked {score} — next in {days} days',
      'settingsLessonPlayback': 'Lesson playback',
      'settingsAutoRepeatLesson': 'Auto-repeat lesson',
      'settingsAutoRepeatLessonSubtitle': 'Start each lesson with the repeat loop enabled by default',
      'settingsAutoCycleVariants': 'Auto-cycle all variants',
      'settingsAutoCycleVariantsSubtitle': 'When a variant finishes, automatically play the next one: Original → Enhanced → Present → Future, then stop',
      'settingsMaintenance': 'Maintenance',
      'settingsFixEverything': 'Fix everything',
      'settingsFixEverythingSubtitle': 'Sync diary, fill missing Q&A and rebuild audio timing in one go',
      'settingsFillQaTranslations': 'Fill missing Q&A translations',
      'settingsFillQaTranslationsSubtitle': 'Generates Q&A pairs not yet translated into your study language',
      'settingsRebuildAudioTiming': 'Rebuild audio timing',
      'settingsRebuildAudioTimingSubtitle': 'Recomputes sentence-highlight sync for all lessons',
      'settingsForceAudioRegen': 'Force audio re-generation',
      'settingsForceAudioRegenSubtitle': 'Re-runs TTS for every lesson (slow). Leave off to only recompute timing from existing files.',
      'settingsJobStarted': 'Started — this may take several minutes',
      'settingsJobError': 'Error: {error}',
      'statsTitle': 'Stats & Streak',
      'refreshTooltipStats': 'Refresh',
      'dayStreak': 'day streak',
      'reviewedToday': '✓ {count} reviewed today',
      'noReviewsToday': 'No reviews yet today',
      'statsOverview': 'Overview',
      'statsTotalReviews': 'Total reviews',
      'statsReviewedTodayLabel': 'Reviewed today',
      'statsNoScores': 'No scores recorded yet.',
      'statsScoreDistribution': 'Score distribution',
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
      'noDiarySentence': 'Aucune entr\u00e9e de journal pour {date}.\nV\u00e9rifiez que le serveur contient cette entr\u00e9e.',
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
      'retryButton': 'Réessayer',
      'refreshButton': 'Actualiser',
      'addButton': 'Ajouter',
      'changeButton': 'Modifier',
      'editTooltip': 'Modifier',
      'removeTooltip': 'Supprimer',
      'confirmTooltip': 'Confirmer',
      'stopButton': 'Arrêter',
      'playAllButton': 'Tout lire',
      'skipButton': 'Passer',
      'refreshTooltip': 'Actualiser',
      'helpTooltip': 'Aide',
      'settingsTooltip': 'Paramètres',
      'navHome': 'Accueil',
      'navReview': 'Révision',
      'navReviewLessons': 'Réviser les leçons',
      'translationExercise': 'Exercice de traduction',
      'serverOnline': 'Serveur en ligne',
      'serverOffline': 'Serveur hors ligne',
      'serverUnreachableNoCache': 'Serveur inaccessible — aucune donnée en cache.',
      'diaryDate': 'Date du journal',
      'diarySentencesFor': 'Phrases pour {date}',
      'diaryTypeSentenceHint': 'Écrivez une phrase…',
      'diaryNoSentences': 'Aucune phrase pour l’instant.',
      'diarySaveToServer': 'Enregistrer sur le serveur',
      'diaryGenerateLessons': 'Générer les leçons',
      'diaryGenerationStarting': 'Démarrage de la génération…',
      'diaryAddSentenceFirst': 'Ajoutez au moins une phrase d’abord.',
      'diaryEntrySaved': '✓ Entrée enregistrée pour {date} ({count} phrase(s))',
      'diarySavedLocally': 'Enregistré localement. Sera synchronisé à la prochaine connexion.\n{error}',
      'diaryCouldNotConnect': 'Impossible de se connecter au serveur.',
      'loginConnectionError': 'Erreur : {error}\n\nVérifiez que l’URL du serveur est correcte et que le serveur est accessible.',
      'homeProgress': 'Progression',
      'homeMastered': 'Maîtrisé',
      'homeInProgress': 'En cours',
      'homeNewTotalEntries': '{newCount} nouveau(x) • {total} entrée(s) au total',
      'homeStudyNow': 'Étudier maintenant',
      'reviewOptionsTooltip': 'Options de révision',
      'originalReview': 'Révision originale',
      'dueForReview': 'À réviser',
      'newLesson': 'Nouvelle leçon',
      'homeRecentlyStudied': 'Récemment étudié',
      'homeNoLessonsStudied': 'Aucune leçon étudiée pour l’instant.',
      'timeAgoJustNow': 'À l’instant',
      'timeAgoDays': 'il y a {count} j',
      'timeAgoHours': 'il y a {count} h',
      'timeAgoMinutes': 'il y a {count} min',
      'lessonsMasteredCount': '{mastered}/{total} maîtrisé(s)',
      'sentenceReviewTitle': 'Révision de phrases',
      'translationExerciseTitle': 'Exercice de traduction',
      'syncAudioTooltip': 'Synchroniser l’audio',
      'syncCurrentSentence': 'Synchroniser la phrase actuelle',
      'syncAllSentencesCount': 'Synchroniser tout ({count} phrases)',
      'statsAndStreakTooltip': 'Stats & Série',
      'reviewRemaining': '{count} restant(s)',
      'offlineShowingCached': 'Hors ligne — révision en cache. Les scores seront synchronisés quand connecté.',
      'offlineLoadNewSentences': 'Hors ligne — synchronisez l’app quand connecté pour charger de nouvelles phrases.',
      'downloadingAudio': 'Téléchargement de l’audio…',
      'audioUnavailable': 'Audio non disponible',
      'audioSynced': 'Audio synchronisé',
      'syncedAudioCount': 'Audio synchronisé pour {count} phrase(s)',
      'allCaughtUp': 'Tout à jour !',
      'noSentencesDue': 'Aucune phrase à réviser pour l’instant.',
      'showTranslation': 'Afficher la traduction',
      'hideTranslation': 'Masquer la traduction',
      'showQa': 'Afficher Q&R ({count} paires)',
      'hideQa': 'Masquer Q&R',
      'howWellDidYouRemember': 'Dans quelle mesure vous en souvenez-vous ?',
      'scoreAgain': 'Encore',
      'scoreHard': 'Difficile',
      'scoreGood': 'Bien',
      'scoreEasy': 'Facile',
      'scoreSavedWillSync': 'Score enregistré (sera synchronisé quand connecté)',
      'scoreSavedLocallyError': 'Score enregistré localement — erreur de sync : {error}',
      'translationAttemptHintWithEnter': 'Votre tentative de traduction (appuyez sur Entrée pour révéler)',
      'translationAttemptLabel': 'Votre tentative de traduction',
      'fontSizeSmall': 'Petit',
      'fontSizeNormal': 'Normal',
      'fontSizeLarge': 'Grand',
      'fontSizeExtraLarge': 'Très grand',
      'cycleVariantsOn': 'Cycle de variantes : activé',
      'cycleVariantsOff': 'Cycle de variantes : désactivé',
      'previousBlock': 'Bloc précédent',
      'nextBlock': 'Bloc suivant',
      'repeatCurrentBlock': 'Répéter le bloc actuel',
      'stopBlockRepeat': 'Arrêter la répétition du bloc',
      'audioNotDownloadedYet': '⏳ Audio non téléchargé — synchronisation en cours, veuillez patienter…',
      'audioNotDownloaded': 'Audio non téléchargé — appuyez sur ▶ ou synchronisez ⟳ pour télécharger',
      'downloadingAudioWait': 'Téléchargement de l’audio… veuillez patienter',
      'contentNotAvailable': 'Contenu non disponible.\nSynchronisez la leçon pour la consulter hors ligne.',
      'noDiaryEntriesFound': '(Aucune entrée de journal trouvée)',
      'couldNotLoadDiaryEntry': 'Impossible de charger l’entrée du journal.\nAppuyez sur sync ou vérifiez la connexion au serveur.\n\nErreur : {error}',
      'markedScore': 'Noté {score}',
      'markedScoreWithInterval': 'Noté {score} — suivant dans {days} jours',
      'settingsLessonPlayback': 'Lecture des leçons',
      'settingsAutoRepeatLesson': 'Répétition automatique',
      'settingsAutoRepeatLessonSubtitle': 'Commencer chaque leçon avec la boucle de répétition activée par défaut',
      'settingsAutoCycleVariants': 'Cycle automatique des variantes',
      'settingsAutoCycleVariantsSubtitle': 'Quand une variante se termine, passer automatiquement à la suivante : Original → Amélioré → Présent → Futur, puis s’arrêter',
      'settingsMaintenance': 'Maintenance',
      'settingsFixEverything': 'Tout corriger',
      'settingsFixEverythingSubtitle': 'Synchroniser le journal, remplir les Q&R manquants et reconstruire le timing audio en une fois',
      'settingsFillQaTranslations': 'Remplir les traductions Q&R manquantes',
      'settingsFillQaTranslationsSubtitle': 'Génère les paires Q&R non encore traduites dans votre langue d’étude',
      'settingsRebuildAudioTiming': 'Reconstruire le timing audio',
      'settingsRebuildAudioTimingSubtitle': 'Recalcule la synchronisation des sous-titres pour toutes les leçons',
      'settingsForceAudioRegen': 'Forcer la re-génération audio',
      'settingsForceAudioRegenSubtitle': 'Relance la TTS pour chaque leçon (lent). Désactivez pour ne recalculer que le timing depuis les fichiers existants.',
      'settingsJobStarted': 'Démarré — cela peut prendre plusieurs minutes',
      'settingsJobError': 'Erreur : {error}',
      'statsTitle': 'Stats & Série',
      'dayStreak': 'jour(s) de série',
      'reviewedToday': '✓ {count} révisé(s) aujourd’hui',
      'noReviewsToday': 'Aucune révision aujourd’hui',
      'statsOverview': 'Aperçu',
      'statsTotalReviews': 'Total des révisions',
      'statsReviewedTodayLabel': 'Révisé aujourd’hui',
      'statsNoScores': 'Aucun score enregistré pour l’instant.',
      'statsScoreDistribution': 'Distribution des scores',
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
      'noDiarySentence': 'No se encontr\u00f3 entrada de diario para {date}.\nAseg\u00farate de que el servidor tenga esta entrada.',
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
      'retryButton': 'Reintentar',
      'refreshButton': 'Actualizar',
      'addButton': 'Añadir',
      'changeButton': 'Cambiar',
      'editTooltip': 'Editar',
      'removeTooltip': 'Eliminar',
      'confirmTooltip': 'Confirmar',
      'stopButton': 'Detener',
      'playAllButton': 'Reproducir todo',
      'skipButton': 'Omitir',
      'refreshTooltip': 'Actualizar',
      'helpTooltip': 'Ayuda',
      'settingsTooltip': 'Ajustes',
      'navHome': 'Inicio',
      'navReview': 'Revisión',
      'navReviewLessons': 'Revisar lecciones',
      'translationExercise': 'Ejercicio de traducción',
      'serverOnline': 'Servidor en línea',
      'serverOffline': 'Servidor sin conexión',
      'serverUnreachableNoCache': 'Servidor no disponible — sin datos en caché.',
      'diaryDate': 'Fecha del diario',
      'diarySentencesFor': 'Frases para {date}',
      'diaryTypeSentenceHint': 'Escribe una frase…',
      'diaryNoSentences': 'Aún no hay frases.',
      'diarySaveToServer': 'Guardar en el servidor',
      'diaryGenerateLessons': 'Generar lecciones',
      'diaryGenerationStarting': 'Iniciando generación…',
      'diaryAddSentenceFirst': 'Añade al menos una frase primero.',
      'diaryEntrySaved': '✓ Entrada guardada para {date} ({count} frase(s))',
      'diarySavedLocally': 'Guardado localmente. Se sincronizará en la próxima conexión.\n{error}',
      'diaryCouldNotConnect': 'No se pudo conectar al servidor.',
      'loginConnectionError': 'Error: {error}\n\nVerifica que la URL del servidor sea correcta y que el servidor sea accesible.',
      'homeProgress': 'Progreso',
      'homeMastered': 'Dominado',
      'homeInProgress': 'En progreso',
      'homeNewTotalEntries': '{newCount} nuevo(s) • {total} entrada(s) en total',
      'homeStudyNow': 'Estudiar ahora',
      'reviewOptionsTooltip': 'Opciones de revisión',
      'originalReview': 'Revisión original',
      'dueForReview': 'Para revisar',
      'newLesson': 'Nueva lección',
      'homeRecentlyStudied': 'Estudiado recientemente',
      'homeNoLessonsStudied': 'Aún no se ha estudiado ninguna lección.',
      'timeAgoJustNow': 'Ahora mismo',
      'timeAgoDays': 'hace {count}d',
      'timeAgoHours': 'hace {count}h',
      'timeAgoMinutes': 'hace {count}min',
      'lessonsMasteredCount': '{mastered}/{total} dominado(s)',
      'sentenceReviewTitle': 'Revisión de frases',
      'translationExerciseTitle': 'Ejercicio de traducción',
      'syncAudioTooltip': 'Sincronizar audio',
      'syncCurrentSentence': 'Sincronizar frase actual',
      'syncAllSentencesCount': 'Sincronizar todo ({count} frases)',
      'statsAndStreakTooltip': 'Estadísticas y racha',
      'reviewRemaining': '{count} restante(s)',
      'offlineShowingCached': 'Sin conexión — mostrando revisión en caché. Las puntuaciones se sincronizarán al conectarse.',
      'offlineLoadNewSentences': 'Sin conexión — sincroniza la app al conectarte para cargar nuevas frases.',
      'downloadingAudio': 'Descargando audio…',
      'audioUnavailable': 'Audio no disponible',
      'audioSynced': 'Audio sincronizado',
      'syncedAudioCount': 'Audio sincronizado para {count} frase(s)',
      'allCaughtUp': '¡Todo al día!',
      'noSentencesDue': 'No hay frases pendientes de revisión ahora mismo.',
      'showTranslation': 'Mostrar traducción',
      'hideTranslation': 'Ocultar traducción',
      'showQa': 'Mostrar P&R ({count} pares)',
      'hideQa': 'Ocultar P&R',
      'howWellDidYouRemember': '¿Qué tan bien lo recordaste?',
      'scoreAgain': 'Otra vez',
      'scoreHard': 'Difícil',
      'scoreGood': 'Bien',
      'scoreEasy': 'Fácil',
      'scoreSavedWillSync': 'Puntuación guardada (se sincronizará al conectarse)',
      'scoreSavedLocallyError': 'Puntuación guardada localmente — error de sincronización: {error}',
      'translationAttemptHintWithEnter': 'Tu intento de traducción (presiona Enter para revelar)',
      'translationAttemptLabel': 'Tu intento de traducción',
      'fontSizeSmall': 'Pequeño',
      'fontSizeNormal': 'Normal',
      'fontSizeLarge': 'Grande',
      'fontSizeExtraLarge': 'Extra grande',
      'cycleVariantsOn': 'Ciclo de variantes: activado',
      'cycleVariantsOff': 'Ciclo de variantes: desactivado',
      'previousBlock': 'Bloque anterior',
      'nextBlock': 'Siguiente bloque',
      'repeatCurrentBlock': 'Repetir bloque actual',
      'stopBlockRepeat': 'Detener repetición de bloque',
      'audioNotDownloadedYet': '⏳ Audio no descargado — sincronizando, espera…',
      'audioNotDownloaded': 'Audio no descargado — pulsa ▶ o sincroniza ⟳ para descargar',
      'downloadingAudioWait': 'Descargando audio… por favor espera',
      'contentNotAvailable': 'Contenido no disponible.\nSincroniza la lección para verla sin conexión.',
      'noDiaryEntriesFound': '(No se encontraron entradas de diario)',
      'couldNotLoadDiaryEntry': 'No se pudo cargar la entrada del diario.\nToca sincronizar o verifica la conexión al servidor.\n\nError: {error}',
      'markedScore': 'Marcado {score}',
      'markedScoreWithInterval': 'Marcado {score} — próximo en {days} días',
      'settingsLessonPlayback': 'Reproducción de lecciones',
      'settingsAutoRepeatLesson': 'Repetición automática',
      'settingsAutoRepeatLessonSubtitle': 'Iniciar cada lección con el bucle de repetición activado por defecto',
      'settingsAutoCycleVariants': 'Ciclo automático de variantes',
      'settingsAutoCycleVariantsSubtitle': 'Cuando termina una variante, reproducir automáticamente la siguiente: Original → Mejorada → Presente → Futuro, luego parar',
      'settingsMaintenance': 'Mantenimiento',
      'settingsFixEverything': 'Arreglar todo',
      'settingsFixEverythingSubtitle': 'Sincronizar diario, completar P&R faltantes y reconstruir el timing de audio en un solo paso',
      'settingsFillQaTranslations': 'Completar traducciones P&R faltantes',
      'settingsFillQaTranslationsSubtitle': 'Genera pares P&R no traducidos aún a tu idioma de estudio',
      'settingsRebuildAudioTiming': 'Reconstruir timing de audio',
      'settingsRebuildAudioTimingSubtitle': 'Recalcula la sincronización de subtítulos para todas las lecciones',
      'settingsForceAudioRegen': 'Forzar re-generación de audio',
      'settingsForceAudioRegenSubtitle': 'Vuelve a ejecutar TTS para cada lección (lento). Desactiva para solo recalcular el timing de los archivos existentes.',
      'settingsJobStarted': 'Iniciado — esto puede tardar varios minutos',
      'settingsJobError': 'Error: {error}',
      'statsTitle': 'Estadísticas y racha',
      'dayStreak': 'días de racha',
      'reviewedToday': '✓ {count} revisado(s) hoy',
      'noReviewsToday': 'Sin revisiones hoy',
      'statsOverview': 'Resumen',
      'statsTotalReviews': 'Total de revisiones',
      'statsReviewedTodayLabel': 'Revisado hoy',
      'statsNoScores': 'Aún no hay puntuaciones registradas.',
      'statsScoreDistribution': 'Distribución de puntuaciones',
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
