import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swiftspeak/aac_es.dart';
import 'package:swiftspeak/l10n/aac_i18n.dart';
import 'package:swiftspeak/l10n/body_parts.dart';
import 'package:swiftspeak/l10n/extra_ui_strings.dart';
import 'package:swiftspeak/l10n/extra_ui_strings_cjk.dart';

enum AppLang {
  english,
  spanish,
  chinese,
  hindi,
  portuguese,
  bengali,
  russian,
  japanese,
  turkish;

  String get code => switch (this) {
        english => 'en',
        spanish => 'es',
        chinese => 'zh',
        hindi => 'hi',
        portuguese => 'pt',
        bengali => 'bn',
        russian => 'ru',
        japanese => 'ja',
        turkish => 'tr',
      };

  Locale get locale => Locale(code == 'zh' ? 'zh' : code);

  String get ttsLanguage => switch (this) {
        english => 'en-US',
        spanish => 'es-ES',
        chinese => 'zh-CN',
        hindi => 'hi-IN',
        portuguese => 'pt-BR',
        bengali => 'bn-IN',
        russian => 'ru-RU',
        japanese => 'ja-JP',
        turkish => 'tr-TR',
      };

  String get englishName => switch (this) {
        english => 'English',
        spanish => 'Spanish',
        chinese => 'Chinese',
        hindi => 'Hindi',
        portuguese => 'Portuguese',
        bengali => 'Bengali',
        russian => 'Russian',
        japanese => 'Japanese',
        turkish => 'Turkish',
      };

  String get nativeName => switch (this) {
        english => 'English',
        spanish => 'Español',
        chinese => '中文',
        hindi => 'हिन्दी',
        portuguese => 'Português',
        bengali => 'বাংলা',
        russian => 'Русский',
        japanese => '日本語',
        turkish => 'Türkçe',
      };

  static AppLang fromCode(String? raw) {
    switch (raw) {
      case 'es':
        return AppLang.spanish;
      case 'zh':
        return AppLang.chinese;
      case 'hi':
        return AppLang.hindi;
      case 'pt':
        return AppLang.portuguese;
      case 'bn':
        return AppLang.bengali;
      case 'ru':
        return AppLang.russian;
      case 'ja':
        return AppLang.japanese;
      case 'tr':
        return AppLang.turkish;
      default:
        return AppLang.english;
    }
  }
}

class AppLanguage extends ChangeNotifier {
  AppLanguage._();
  static final AppLanguage instance = AppLanguage._();

  static const _prefKey = 'app_language';

  AppLang _lang = AppLang.english;

  AppLang get lang => _lang;

  String get code => _lang.code;

  bool get isSpanish => _lang == AppLang.spanish;

  Locale get locale => _lang.locale;

  String get ttsLanguage => _lang.ttsLanguage;

  String get englishName => _lang.englishName;

  String get replyLanguageRule =>
      'Write every user-facing sentence in ${_lang.englishName}. Use simple, clear ${_lang.englishName}.';

  String get suggestionLanguageRule =>
      'Write suggestions in ${_lang.englishName}.';

  String aacLabel(String english) {
    if (_lang == AppLang.english) return english;
    final table = _lang == AppLang.spanish
        ? aacEs
        : (aacI18n[_lang.code] ?? const <String, String>{});
    return table[english] ?? table[english.toLowerCase()] ?? english;
  }

  String t(String key, [Map<String, String>? args]) {
    final table = uiTables[_lang.code] ?? _en;
    var value = table[key] ?? _en[key] ?? key;
    if (args != null) {
      args.forEach((name, replacement) {
        value = value.replaceAll('{$name}', replacement);
      });
    }
    return value;
  }

  String moodLabel(String stored) {
    switch (stored) {
      case 'Good':
        return t('moodGood');
      case 'Okay':
        return t('moodOkay');
      case 'Neutral':
        return t('moodNeutral');
      case 'Not Good':
        return t('moodNotGood');
      case 'Difficult':
        return t('moodDifficult');
      default:
        return stored;
    }
  }

  String monthLabel(String stored) {
    if (stored == 'All') return t('all');
    return t('month$stored');
  }

  String yearLabel(String stored) {
    if (stored == 'All') return t('all');
    return stored;
  }

  String painLabel(String stored) {
    switch (stored) {
      case 'Low':
        return t('painLow');
      case 'Moderate':
        return t('painModerate');
      case 'High':
        return t('painHigh');
      case 'None':
        return t('painNone');
      default:
        return stored;
    }
  }

  String tagLabel(String tag) {
    switch (tag) {
      case 'Fatigue':
        return t('tagFatigue');
      case 'Symptoms':
        return t('tagSymptoms');
      case 'Getting Started':
        return t('tagGettingStarted');
      case 'FAQs':
        return t('tagFaqs');
      case 'Medication':
        return t('tagMedication');
      case 'Caregiver':
        return t('tagCaregiver');
      case 'Appointments':
        return t('tagAppointments');
      default:
        return tag;
    }
  }

  String bodyPartLabel(String id) {
    var raw = id.replaceAll(' ', '');
    if (raw == 'spot9') return t('bodyLowerAbdomen');

    String? lookup(String partId) {
      final key = 'body$partId';
      final table = uiTables[_lang.code];
      return table?[key] ?? _en[key];
    }

    final exact = lookup(raw);
    if (exact != null) return exact;

    if (raw.startsWith('Side')) raw = raw.substring(4);
    if (raw.startsWith('Back')) raw = raw.substring(4);

    final stripped = lookup(raw);
    if (stripped != null) return stripped;

    const unpaired = {
      'LeftHead': 'Head',
      'RightHead': 'Head',
      'LeftNeck': 'Neck',
      'RightNeck': 'Neck',
      'LeftChest': 'Chest',
      'RightChest': 'Chest',
      'LeftAbdomen': 'Abdomen',
      'RightAbdomen': 'Abdomen',
      'LeftStomach': 'Stomach',
      'RightStomach': 'Stomach',
    };
    final fallbackId = unpaired[raw] ?? raw;
    return lookup(fallbackId) ??
        fallbackId.replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        );
  }

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _lang = AppLang.fromCode(prefs.getString(_prefKey));
    notifyListeners();
  }

  Future<void> setLang(AppLang lang) async {
    if (_lang == lang) return;
    _lang = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, lang.code);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'language': lang.code},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> applyFromUserDoc(Map<String, dynamic>? data) async {
    final raw = data?['language'] as String?;
    if (raw == null || raw.isEmpty) return;
    await setLang(AppLang.fromCode(raw));
  }
}

class AppLangBuilder extends StatelessWidget {
  const AppLangBuilder({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    String Function(String key, [Map<String, String>? args]) t,
  ) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) => builder(context, AppLanguage.instance.t),
    );
  }
}

extension AppLanguageText on BuildContext {
  String tr(String key, [Map<String, String>? args]) =>
      AppLanguage.instance.t(key, args);
}

Map<String, String> _mergeUi(
  Map<String, String> base,
  Map<String, String> bodyParts,
) =>
    Map<String, String>.from(base)..addAll(bodyParts);

final uiTables = <String, Map<String, String>>{
  'en': _mergeUi(_en, bodyPartsEn),
  'es': _mergeUi(_es, bodyPartsEs),
  'zh': _mergeUi(uiZh, bodyPartsZh),
  'hi': _mergeUi(uiHi, bodyPartsHi),
  'pt': _mergeUi(uiPt, bodyPartsPt),
  'bn': _mergeUi(uiBn, bodyPartsBn),
  'ru': _mergeUi(uiRu, bodyPartsRu),
  'ja': _mergeUi(uiJa, bodyPartsJa),
  'tr': _mergeUi(uiTr, bodyPartsTr),
};

const _en = <String, String>{
  'language': 'Language',
  'languageHelp': 'This changes the app and the keyboard.',
  'english': 'English',
  'spanish': 'Spanish',
  'login': 'Login',
  'signUp': 'Sign Up',
  'email': 'Email',
  'password': 'Password',
  'createAccount': 'Create Account',
  'creating': 'Creating...',
  'selectRole': 'Select Role',
  'patient': 'Patient',
  'hospitalStaff': 'Hospital Staff',
  'yourNameOptional': 'Your name (optional)',
  'signUpIfNeeded': "Sign up if you don't have an account already:",
  'welcome': 'Welcome',
  'profile': 'Profile',
  'patientTools': 'Patient Tools',
  'bodyCheck': 'Body Check',
  'bodyCheckHint': 'Tap the areas of pain',
  'moodCheck': 'Mood Check',
  'moodCheckHint': 'How are you feeling?',
  'communication': 'Communication',
  'communicationHint': 'Express your needs easily',
  'aiChatbot': 'AI Chatbot',
  'aiChatbotHint': 'Get personalized AI responses',
  'communityPage': 'Community Page',
  'communityHint': 'Share and find recovery support',
  'logOut': 'Log Out',
  'displayName': 'Display name',
  'displayNameHint': 'How you want to be called',
  'saveDisplayName': 'Save display name',
  'saving': 'Saving…',
  'aLittleAboutYou': 'A little about you',
  'surveyEmptyHelp':
      'Word suggestions are general until you add answers. After you finish, Communication, Community, and Chatbot use this questionnaire to predict your words.',
  'surveyFilledHelp':
      'Word suggestions now use these answers in Communication, Community, and Chatbot.',
  'addQuestionnaire': 'Add questionnaire',
  'updateQuestionnaire': 'Update questionnaire',
  'account': 'Account',
  'changePassword': 'Change password',
  'currentPassword': 'Current password',
  'newPassword': 'New password',
  'confirmNewPassword': 'Confirm new password',
  'cancel': 'Cancel',
  'update': 'Update',
  'notSignedIn': 'Not signed in',
  'passwordHidden':
      'Your password is never shown. Use change password to update it.',
  'communicate': 'Communicate',
  'selectOrSpeak': 'Select or speak a message',
  'suggestionsUseSurvey': 'Word suggestions use your questionnaire',
  'suggestionsGeneral':
      'Word suggestions are general until you add answers in Profile',
  'tidyUp': 'Tidy Up',
  'undo': 'Undo',
  'space': 'Space',
  'done': 'Done',
  'caps': 'CAPS',
  'predicting': 'Predicting…',
  'suggestionsAsYouType': 'Suggestions appear as you type',
  'community': 'Community',
  'typeMessage': 'Type your message...',
  'askAi': 'Ask AI',
  'askAiHelp': 'Tell AI how to change the message.',
  'howAreYouToday': 'How are you doing today?',
  'moodGood': 'Good',
  'moodOkay': 'Okay',
  'moodNeutral': 'Neutral',
  'moodNotGood': 'Not Good',
  'moodDifficult': 'Difficult',
  'moodHistory': 'Mood Check history',
  'moodHistoryTitle': 'Mood Check History',
  'stressLevel': 'Stress Level',
  'energyLevel': 'Energy Level',
  'hopefulness': 'Hopefulness',
  'confidenceRecovery': 'Confidence in Recovery',
  'nextPage': 'Next page',
  'moodResults': 'Mood Check Results',
  'hereAreResults': "Here's your results:",
  'yourMoodToday': 'Your Mood Today:',
  'yourStressLevel': 'Your Stress Level:',
  'yourEnergyLevel': 'Your Energy Level:',
  'yourHopefulnessLevel': 'Your Hopefulness Level:',
  'yourConfidenceLevel': 'Your Confidence Level:',
  'aiInsight': 'AI Insight:',
  'generatingInsight': 'Generating insight...',
  'savedId': 'Saved (id: {id})',
  'backToHome': 'Back to Home',
  'pleaseLogIn': 'Please log in first.',
  'month': 'Month',
  'year': 'Year',
  'all': 'All',
  'monthJanuary': 'January',
  'monthFebruary': 'February',
  'monthMarch': 'March',
  'monthApril': 'April',
  'monthMay': 'May',
  'monthJune': 'June',
  'monthJuly': 'July',
  'monthAugust': 'August',
  'monthSeptember': 'September',
  'monthOctober': 'October',
  'monthNovember': 'November',
  'monthDecember': 'December',
  'justNow': 'Just now',
  'noResultsFound': 'No results found',
  'notLoggedIn': 'Not logged in.',
  'entryNotFound': 'Entry not found.',
  'noInsightSaved': '(No insight saved)',
  'aiRecommendation': 'AI Recommendation',
  'yourChats': 'Your Chats',
  'newChat': 'New Chat',
  'chatN': 'Chat {n}',
  'textToSpeech': 'Text-to-Speech',
  'helloHelp': 'Hello! How can I help you today?',
  'aiError': 'AI Error: {error}',
  'aiRecPrefix': 'AI Recommendation:',
  'aiRecError': 'AI Recommendation Error: {error}',
  'noChatsYet': 'No chats yet.',
  'openingLatestChat': 'Opening your latest chat...',
  'failedToOpenChat': 'Failed to open chat: {error}',
  'failedToCreateChat': 'Failed to create chat: {error}',
  'sendFailed': 'Send failed: {error}',
  'recFailed': 'Recommendation failed: {error}',
  'ttsFailed': 'TTS failed: {error}',
  'newChatTitle': 'New chat',
  'history': 'History',
  'bodyCheckHelp':
      'Drag horizontally to rotate. Markers track the body — Front, Back, Left Side, and Right Side.',
  'dragToRotate': 'Drag left or right to rotate',
  'painLevel': 'Pain Level',
  'painLow': 'Low',
  'painModerate': 'Moderate',
  'painHigh': 'High',
  'painNone': 'None',
  'submit': 'Submit',
  'bodyCheckResults': 'Body Check Results',
  'bodyCheckHistory': 'Body Check History',
  'painSummary': 'Pain Summary',
  'loading': 'Loading...',
  'noPainToday': 'No pain reported today. Great job!',
  'failedSubmitBody': 'Failed to submit body check: {error}',
  'failedLoadBody': 'Failed to load body check: {error}',
  'painLevelColon': 'Pain Level: {level}',
  'noDataFound': 'No data found for this record.',
  'viewFront': 'Front',
  'viewBack': 'Back',
  'viewLeft': 'Left Side',
  'viewRight': 'Right Side',
  'forYou': 'For you',
  'latest': 'Latest',
  'gettingStarted': 'Getting Started',
  'unanswered': 'Unanswered',
  'faqs': 'FAQs',
  'yourQuestions': 'Your questions',
  'saved': 'Saved',
  'feedForYou': 'Conversations for you',
  'feedAll': 'All conversations',
  'feedLatest': 'Latest conversations',
  'feedGettingStarted': 'Getting started',
  'feedUnanswered': 'Unanswered questions',
  'feedFaqs': 'FAQs',
  'feedYourQuestions': 'Questions you asked',
  'feedSaved': 'Saved conversations',
  'emptyYourQuestions':
      'You have not asked a question yet. Tap Ask the Community to post one.',
  'emptySaved':
      'No saved conversations yet. Tap the bookmark on a post to save it here.',
  'emptyPosts':
      'No posts here yet. Ask the community so other people can see it.',
  'recoveryMember': 'Recovery member',
  'caregiver': 'Caregiver',
  'searchCommunity': 'Search community',
  'communityRules': 'Community rules',
  'notifications': 'Notifications',
  'closeSearch': 'Close search',
  'search': 'Search',
  'couldNotLoadCommunity':
      'Could not load the community. Check that you are signed in, then try again.',
  'tryAgain': 'Try again',
  'safetyBanner':
      'This community shares lived experience, not medical advice. For urgent symptoms, contact your care team or local emergency services.',
  'askTheCommunity': 'Ask the Community',
  'iAmA': 'I am a',
  'titleForQuestion': 'Title for your question',
  'writeQuestion': 'Write the question. Use @name to mention someone.',
  'tags': 'Tags',
  'post': 'Post',
  'translatePost': 'Translate',
  'showOriginal': 'Show original',
  'translatingPost': 'Translating…',
  'translateFailed': 'Could not translate: {error}',
  'pleaseSignInToPost': 'Please sign in to post.',
  'pleaseSignInToReply': 'Please sign in to reply.',
  'reportConversation': 'Report this conversation?',
  'reportConversationHelp':
      'This will hide the post from your feed. Use this if the conversation is harmful, spam, or unsafe.',
  'report': 'Report',
  'thanksReported':
      'Thanks. This conversation was reported and hidden from your feed.',
  'blockPerson': 'Block this person?',
  'blockPersonHelp':
      'You will no longer see posts from this person in your community feed.',
  'block': 'Block',
  'personBlocked': 'This person is blocked. You will not see their posts.',
  'more': 'More',
  'saveConversation': 'Save conversation',
  'removeSave': 'Remove save',
  'beforeSymptoms': 'Before you post in Symptoms',
  'beforeSymptomsHelp':
      'Are you experiencing severe or worsening symptoms, chest pain, trouble breathing, uncontrolled bleeding, or feel unsafe?',
  'yes': 'Yes',
  'no': 'No',
  'tagFatigue': 'Fatigue',
  'tagSymptoms': 'Symptoms',
  'tagGettingStarted': 'Getting Started',
  'tagFaqs': 'FAQs',
  'tagMedication': 'Medication',
  'tagCaregiver': 'Caregiver',
  'tagAppointments': 'Appointments',
  'rulesIntro':
      'This space is for lived experience. It is not clinical guidance.',
  'skip': 'Skip',
  'finish': 'Finish',
  'next': 'Next',
  'back': 'Back',
  'questionNofM': 'Question {n} of {m}',
  'typeAsMuch': 'Type as much as you want',
  'survey_pets_title': 'Tell us about pets in your life.',
  'survey_pets_hint':
      'If you have pets, what are their names, and what do they like to do? If not, what animals do you like, and why?',
  'survey_fun_title': 'What do you like to do for fun?',
  'survey_fun_hint':
      'Games, music, shows, being outside, or anything else. What makes those things special to you?',
  'survey_people_title': 'Who do you like spending time with?',
  'survey_people_hint':
      'Family, friends, caregivers, or others. What do you enjoy doing together?',
  'survey_comfort_title': 'When a day is hard, what helps you feel better?',
  'survey_comfort_hint':
      'Rest, music, visitors, quiet, talking, fresh air, or something else. How does it help?',
  'survey_food_title': 'What foods or drinks do you love?',
  'survey_food_hint':
      'Favorites, snacks, drinks, and when you like them. Any foods you do not want?',
  'survey_home_title': 'What makes a day at home or in care feel good?',
  'survey_home_hint':
      'People who help you, routines, places, or little things that make you comfortable.',
  'survey_names_title': 'What should people call you?',
  'survey_names_hint':
      'Your name, nicknames, or words you like. Anything you do not want people to call you?',
  'survey_talk_title': 'What do you most often want to say?',
  'survey_talk_hint':
      'To nurses, family, or friends. Requests, feelings, jokes, or questions you wish were easier to say.',
  'survey_routine_title':
      'What does a usual morning or evening look like for you?',
  'survey_routine_hint':
      'What you like to do first, what you need help with, and what you look forward to.',
  'survey_more_title': 'What else should we know about you?',
  'survey_more_hint':
      'Favorite shows, songs, places, jokes, stories, or anything that helps us understand you better.',
  'bodyLowerAbdomen': 'Lower abdomen',
  'bodyLeftHip': 'Left hip',
  'bodyRightHip': 'Right hip',
  'bodyLeftElbow': 'Left upper arm',
  'bodyRightElbow': 'Right upper arm',
  'bodyLeftHand': 'Left forearm',
  'bodyRightHand': 'Right forearm',
  'bodyChest': 'Chest',
  'bodyHead': 'Head',
  'bodyLowerBack': 'Lower back',
};

const _es = <String, String>{
  'language': 'Idioma',
  'languageHelp': 'Esto cambia la aplicación y el teclado.',
  'english': 'Inglés',
  'spanish': 'Español',
  'login': 'Iniciar sesión',
  'signUp': 'Registrarse',
  'email': 'Correo',
  'password': 'Contraseña',
  'createAccount': 'Crear cuenta',
  'creating': 'Creando...',
  'selectRole': 'Elegir rol',
  'patient': 'Paciente',
  'hospitalStaff': 'Personal del hospital',
  'yourNameOptional': 'Tu nombre (opcional)',
  'signUpIfNeeded': 'Regístrate si todavía no tienes una cuenta:',
  'welcome': 'Bienvenida',
  'profile': 'Perfil',
  'patientTools': 'Herramientas del paciente',
  'bodyCheck': 'Revisión del cuerpo',
  'bodyCheckHint': 'Toca las zonas de dolor',
  'moodCheck': 'Revisión de ánimo',
  'moodCheckHint': '¿Cómo te sientes?',
  'communication': 'Comunicación',
  'communicationHint': 'Expresa tus necesidades',
  'aiChatbot': 'Chat de IA',
  'aiChatbotHint': 'Recibe respuestas personalizadas',
  'communityPage': 'Comunidad',
  'communityHint': 'Comparte y encuentra apoyo',
  'logOut': 'Cerrar sesión',
  'displayName': 'Nombre para mostrar',
  'displayNameHint': 'Cómo quieres que te llamen',
  'saveDisplayName': 'Guardar nombre',
  'saving': 'Guardando…',
  'aLittleAboutYou': 'Un poco sobre ti',
  'surveyEmptyHelp':
      'Las sugerencias son generales hasta que agregues respuestas. Después, Comunicación, Comunidad y el chat las usan para predecir tus palabras.',
  'surveyFilledHelp':
      'Las sugerencias ya usan estas respuestas en Comunicación, Comunidad y el chat.',
  'addQuestionnaire': 'Agregar cuestionario',
  'updateQuestionnaire': 'Actualizar cuestionario',
  'account': 'Cuenta',
  'changePassword': 'Cambiar contraseña',
  'currentPassword': 'Contraseña actual',
  'newPassword': 'Nueva contraseña',
  'confirmNewPassword': 'Confirmar contraseña',
  'cancel': 'Cancelar',
  'update': 'Actualizar',
  'notSignedIn': 'No has iniciado sesión',
  'passwordHidden':
      'Tu contraseña nunca se muestra. Usa cambiar contraseña para actualizarla.',
  'communicate': 'Comunicar',
  'selectOrSpeak': 'Elige o di un mensaje',
  'suggestionsUseSurvey': 'Las sugerencias usan tu cuestionario',
  'suggestionsGeneral':
      'Las sugerencias son generales hasta que agregues respuestas en Perfil',
  'tidyUp': 'Corregir',
  'undo': 'Deshacer',
  'space': 'Espacio',
  'done': 'Listo',
  'caps': 'MAYÚS',
  'predicting': 'Prediciendo…',
  'suggestionsAsYouType': 'Sugerencias al escribir',
  'community': 'Comunidad',
  'typeMessage': 'Escribe tu mensaje...',
  'askAi': 'Preguntar a la IA',
  'askAiHelp': 'Dile a la IA cómo cambiar el mensaje.',
  'howAreYouToday': '¿Cómo te sientes hoy?',
  'moodGood': 'Bien',
  'moodOkay': 'Regular',
  'moodNeutral': 'Neutral',
  'moodNotGood': 'Mal',
  'moodDifficult': 'Difícil',
  'moodHistory': 'Historial de ánimo',
  'moodHistoryTitle': 'Historial de ánimo',
  'stressLevel': 'Nivel de estrés',
  'energyLevel': 'Nivel de energía',
  'hopefulness': 'Esperanza',
  'confidenceRecovery': 'Confianza en la recuperación',
  'nextPage': 'Siguiente',
  'moodResults': 'Resultados de ánimo',
  'hereAreResults': 'Estos son tus resultados:',
  'yourMoodToday': 'Tu ánimo de hoy:',
  'yourStressLevel': 'Tu nivel de estrés:',
  'yourEnergyLevel': 'Tu nivel de energía:',
  'yourHopefulnessLevel': 'Tu nivel de esperanza:',
  'yourConfidenceLevel': 'Tu nivel de confianza:',
  'aiInsight': 'Idea de la IA:',
  'generatingInsight': 'Creando idea...',
  'savedId': 'Guardado (id: {id})',
  'backToHome': 'Volver al inicio',
  'pleaseLogIn': 'Inicia sesión primero.',
  'month': 'Mes',
  'year': 'Año',
  'all': 'Todos',
  'monthJanuary': 'Enero',
  'monthFebruary': 'Febrero',
  'monthMarch': 'Marzo',
  'monthApril': 'Abril',
  'monthMay': 'Mayo',
  'monthJune': 'Junio',
  'monthJuly': 'Julio',
  'monthAugust': 'Agosto',
  'monthSeptember': 'Septiembre',
  'monthOctober': 'Octubre',
  'monthNovember': 'Noviembre',
  'monthDecember': 'Diciembre',
  'justNow': 'Ahora',
  'noResultsFound': 'No hay resultados',
  'notLoggedIn': 'No has iniciado sesión.',
  'entryNotFound': 'No se encontró el registro.',
  'noInsightSaved': '(No hay idea guardada)',
  'aiRecommendation': 'Recomendación de IA',
  'yourChats': 'Tus chats',
  'newChat': 'Chat nuevo',
  'chatN': 'Chat {n}',
  'textToSpeech': 'Voz',
  'helloHelp': '¡Hola! ¿Cómo te puedo ayudar hoy?',
  'aiError': 'Error de IA: {error}',
  'aiRecPrefix': 'Recomendación de IA:',
  'aiRecError': 'Error de recomendación: {error}',
  'noChatsYet': 'Aún no hay chats.',
  'openingLatestChat': 'Abriendo tu chat más reciente...',
  'failedToOpenChat': 'No se pudo abrir el chat: {error}',
  'failedToCreateChat': 'No se pudo crear el chat: {error}',
  'sendFailed': 'No se pudo enviar: {error}',
  'recFailed': 'No se pudo crear la recomendación: {error}',
  'ttsFailed': 'No se pudo leer el texto: {error}',
  'newChatTitle': 'Chat nuevo',
  'history': 'Historial',
  'bodyCheckHelp':
      'Arrastra a los lados para girar. Los marcadores siguen el cuerpo: frente, espalda, lado izquierdo y lado derecho.',
  'dragToRotate': 'Arrastra a la izquierda o a la derecha para girar',
  'painLevel': 'Nivel de dolor',
  'painLow': 'Bajo',
  'painModerate': 'Moderado',
  'painHigh': 'Alto',
  'painNone': 'Ninguno',
  'submit': 'Enviar',
  'bodyCheckResults': 'Resultados del cuerpo',
  'bodyCheckHistory': 'Historial del cuerpo',
  'painSummary': 'Resumen del dolor',
  'loading': 'Cargando...',
  'noPainToday': 'Hoy no se reportó dolor. ¡Muy bien!',
  'failedSubmitBody': 'No se pudo enviar la revisión: {error}',
  'failedLoadBody': 'No se pudo cargar la revisión: {error}',
  'painLevelColon': 'Nivel de dolor: {level}',
  'noDataFound': 'No hay datos para este registro.',
  'viewFront': 'Frente',
  'viewBack': 'Espalda',
  'viewLeft': 'Lado izquierdo',
  'viewRight': 'Lado derecho',
  'forYou': 'Para ti',
  'latest': 'Recientes',
  'gettingStarted': 'Primeros pasos',
  'unanswered': 'Sin respuesta',
  'faqs': 'Preguntas',
  'yourQuestions': 'Tus preguntas',
  'saved': 'Guardados',
  'feedForYou': 'Conversaciones para ti',
  'feedAll': 'Todas las conversaciones',
  'feedLatest': 'Conversaciones recientes',
  'feedGettingStarted': 'Primeros pasos',
  'feedUnanswered': 'Preguntas sin respuesta',
  'feedFaqs': 'Preguntas frecuentes',
  'feedYourQuestions': 'Preguntas que hiciste',
  'feedSaved': 'Conversaciones guardadas',
  'emptyYourQuestions':
      'Todavía no has hecho una pregunta. Toca Preguntar a la comunidad para publicar una.',
  'emptySaved':
      'Aún no hay conversaciones guardadas. Toca el marcador de una publicación para guardarla aquí.',
  'emptyPosts':
      'Aún no hay publicaciones. Pregunta a la comunidad para que otras personas lo vean.',
  'recoveryMember': 'En recuperación',
  'caregiver': 'Cuidador',
  'searchCommunity': 'Buscar en la comunidad',
  'communityRules': 'Reglas de la comunidad',
  'notifications': 'Notificaciones',
  'closeSearch': 'Cerrar búsqueda',
  'search': 'Buscar',
  'couldNotLoadCommunity':
      'No se pudo cargar la comunidad. Comprueba que iniciaste sesión e inténtalo de nuevo.',
  'tryAgain': 'Intentar de nuevo',
  'safetyBanner':
      'Esta comunidad comparte experiencias, no consejos médicos. Si hay síntomas urgentes, contacta a tu equipo de cuidado o a emergencias.',
  'askTheCommunity': 'Preguntar a la comunidad',
  'iAmA': 'Soy',
  'titleForQuestion': 'Título de tu pregunta',
  'writeQuestion': 'Escribe la pregunta. Usa @nombre para mencionar a alguien.',
  'tags': 'Etiquetas',
  'post': 'Publicar',
  'translatePost': 'Traducir',
  'showOriginal': 'Ver original',
  'translatingPost': 'Traduciendo…',
  'translateFailed': 'No se pudo traducir: {error}',
  'pleaseSignInToPost': 'Inicia sesión para publicar.',
  'pleaseSignInToReply': 'Inicia sesión para responder.',
  'reportConversation': '¿Reportar esta conversación?',
  'reportConversationHelp':
      'Esto ocultará la publicación de tu lista. Úsalo si es dañina, spam o insegura.',
  'report': 'Reportar',
  'thanksReported':
      'Gracias. Esta conversación fue reportada y oculta de tu lista.',
  'blockPerson': '¿Bloquear a esta persona?',
  'blockPersonHelp':
      'Ya no verás publicaciones de esta persona en la comunidad.',
  'block': 'Bloquear',
  'personBlocked': 'Esta persona está bloqueada. No verás sus publicaciones.',
  'more': 'Más',
  'saveConversation': 'Guardar conversación',
  'removeSave': 'Quitar de guardados',
  'beforeSymptoms': 'Antes de publicar en Síntomas',
  'beforeSymptomsHelp':
      '¿Tienes síntomas graves o que empeoran, dolor en el pecho, dificultad para respirar, sangrado que no para o te sientes en peligro?',
  'yes': 'Sí',
  'no': 'No',
  'tagFatigue': 'Cansancio',
  'tagSymptoms': 'Síntomas',
  'tagGettingStarted': 'Primeros pasos',
  'tagFaqs': 'Preguntas',
  'tagMedication': 'Medicamento',
  'tagCaregiver': 'Cuidador',
  'tagAppointments': 'Citas',
  'rulesIntro':
      'Este espacio es para experiencias vividas. No es orientación clínica.',
  'skip': 'Omitir',
  'finish': 'Terminar',
  'next': 'Siguiente',
  'back': 'Atrás',
  'questionNofM': 'Pregunta {n} de {m}',
  'typeAsMuch': 'Escribe todo lo que quieras',
  'survey_pets_title': 'Cuéntanos sobre las mascotas en tu vida.',
  'survey_pets_hint':
      'Si tienes mascotas, ¿cómo se llaman y qué les gusta hacer? Si no, ¿qué animales te gustan y por qué?',
  'survey_fun_title': '¿Qué te gusta hacer por diversión?',
  'survey_fun_hint':
      'Juegos, música, programas, estar afuera u otra cosa. ¿Qué hace especiales esas cosas para ti?',
  'survey_people_title': '¿Con quién te gusta pasar el tiempo?',
  'survey_people_hint':
      'Familia, amistades, cuidadores u otras personas. ¿Qué disfrutan hacer juntos?',
  'survey_comfort_title':
      'Cuando un día es difícil, ¿qué te ayuda a sentirte mejor?',
  'survey_comfort_hint':
      'Descanso, música, visitas, silencio, hablar, aire fresco u otra cosa. ¿Cómo te ayuda?',
  'survey_food_title': '¿Qué comidas o bebidas te encantan?',
  'survey_food_hint':
      'Favoritas, botanas, bebidas y cuándo las quieres. ¿Hay comidas que no quieres?',
  'survey_home_title':
      '¿Qué hace que un día en casa o en cuidado se sienta bien?',
  'survey_home_hint':
      'Personas que te ayudan, rutinas, lugares o detalles que te dan comodidad.',
  'survey_names_title': '¿Cómo quieres que te llamen?',
  'survey_names_hint':
      'Tu nombre, apodos o palabras que te gustan. ¿Hay algo que no quieres que te digan?',
  'survey_talk_title': '¿Qué quieres decir con más frecuencia?',
  'survey_talk_hint':
      'A enfermeras, familia o amistades. Pedidos, sentimientos, bromas o preguntas que quisieras decir con más facilidad.',
  'survey_routine_title': '¿Cómo es una mañana o noche habitual para ti?',
  'survey_routine_hint':
      'Qué te gusta hacer primero, en qué necesitas ayuda y qué esperas con gusto.',
  'survey_more_title': '¿Qué más debemos saber de ti?',
  'survey_more_hint':
      'Programas, canciones, lugares, bromas, historias o cualquier cosa que nos ayude a conocerte mejor.',
  'bodyLowerAbdomen': 'Abdomen bajo',
  'bodyLeftHip': 'Cadera izquierda',
  'bodyRightHip': 'Cadera derecha',
  'bodyLeftElbow': 'Brazo izquierdo',
  'bodyRightElbow': 'Brazo derecho',
  'bodyLeftHand': 'Antebrazo izquierdo',
  'bodyRightHand': 'Antebrazo derecho',
  'bodyChest': 'Pecho',
  'bodyHead': 'Cabeza',
  'bodyLowerBack': 'Espalda baja',
};
