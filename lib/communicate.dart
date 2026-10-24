import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:swiftspeak/aac_access_settings.dart';
import 'package:swiftspeak/ai_chat_service.dart';
import 'package:swiftspeak/app_keyboard.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/typing_prediction.dart';

part 'aac_core_fringe.dart';
part 'aac_custom_words.dart';
part 'aac_button_edits.dart';

class Communicate extends StatelessWidget {
  const Communicate({super.key});

  @override
  Widget build(BuildContext context) {
    return const AacBoardPage(
      title: 'Communicate',
      items: AacVocabulary.home,
      isHome: true,
    );
  }
}

enum TtsTone {
  neutral,
  urgent,
  affirming,
  firm,
  happy,
  sad,
  angry,
  scared,
  anxious,
  gentle,
}

extension TtsToneSettings on TtsTone {
  double get pitch {
    switch (this) {
      case TtsTone.urgent:
        return 1.15;
      case TtsTone.affirming:
        return 1.2;
      case TtsTone.firm:
        return 0.8;
      case TtsTone.happy:
        return 1.25;
      case TtsTone.sad:
        return 0.75;
      case TtsTone.angry:
        return 0.9;
      case TtsTone.scared:
        return 1.3;
      case TtsTone.anxious:
        return 1.18;
      case TtsTone.gentle:
        return 0.95;
      case TtsTone.neutral:
        return 1.0;
    }
  }

  double get rate {
    switch (this) {
      case TtsTone.urgent:
        return 0.55;
      case TtsTone.affirming:
        return 0.48;
      case TtsTone.firm:
        return 0.4;
      case TtsTone.happy:
        return 0.5;
      case TtsTone.sad:
        return 0.35;
      case TtsTone.angry:
        return 0.55;
      case TtsTone.scared:
        return 0.52;
      case TtsTone.anxious:
        return 0.5;
      case TtsTone.gentle:
        return 0.4;
      case TtsTone.neutral:
        return 0.45;
    }
  }

  double get volume {
    switch (this) {
      case TtsTone.urgent:
      case TtsTone.angry:
        return 1.0;
      case TtsTone.sad:
      case TtsTone.gentle:
        return 0.85;
      default:
        return 0.95;
    }
  }

  static TtsTone fromPhrase(String phrase) {
    final text = phrase.toLowerCase();
    if (text.contains('emergency') ||
        text.contains("can't breathe") ||
        text.contains('allergic') ||
        text.contains('it hurts')) {
      return TtsTone.urgent;
    }
    if (text == 'yes') return TtsTone.affirming;
    if (text == 'no' || text == 'stop') return TtsTone.firm;
    if (text.contains('happy') ||
        text.contains('proud') ||
        text.contains('thank') ||
        text.contains('grateful') ||
        text.contains('love')) {
      return TtsTone.happy;
    }
    if (text.contains('sad') ||
        text.contains('lonely') ||
        text.contains('sorry')) {
      return TtsTone.sad;
    }
    if (text.contains('angry') ||
        text.contains('frustrated') ||
        text.contains('tired of')) {
      return TtsTone.angry;
    }
    if (text.contains('scared')) {
      return TtsTone.scared;
    }
    if (text.contains('anxious') ||
        text.contains('worried') ||
        text.contains('overwhelmed')) {
      return TtsTone.anxious;
    }
    if (text.contains('please') ||
        text.contains('okay') ||
        text.contains('rest')) {
      return TtsTone.gentle;
    }
    return TtsTone.neutral;
  }
}

class AacItem {
  const AacItem({
    required this.label,
    required this.icon,
    required this.color,
    this.speak,
    this.children,
    this.tileColor,
    this.foregroundColor,
    this.tone,
    this.customId,
    this.originalLabel,
    this.imagePath,
    this.audioPath,
  });

  const AacItem.word(
    this.label, {
    required this.icon,
    this.color = Colors.indigo,
  })  : speak = label,
        children = null,
        tileColor = null,
        foregroundColor = null,
        tone = null,
        customId = null,
        originalLabel = null,
        imagePath = null,
        audioPath = null;

  final String label;
  final IconData icon;
  final Color color;
  final String? speak;
  final List<AacItem>? children;
  final Color? tileColor;
  final Color? foregroundColor;
  final TtsTone? tone;
  final String? customId;
  final String? originalLabel;
  final String? imagePath;
  final String? audioPath;

  bool get isFolder => children != null;
  bool get isCustom => customId != null && customId != AacVocabulary.addWordId;
  bool get isAddWord => customId == AacVocabulary.addWordId;
  String get identity => customId ?? originalLabel ?? label;
  bool get hasPhoto => imagePath != null && imagePath!.isNotEmpty;
  bool get hasSound => audioPath != null && audioPath!.isNotEmpty;

  /// Most buttons speak the word on the tile so people can build sentences.
  /// Emergency keeps a full help phrase.
  String get displayLabel => AppLanguage.instance.aacLabel(label);

  String get spokenText {
    if (identity == 'Emergency' || originalLabel == 'Emergency') {
      return AppLanguage.instance.aacLabel(
        speak ?? 'I need emergency help right now',
      );
    }
    return displayLabel;
  }

  TtsTone get effectiveTone =>
      tone ?? TtsToneSettings.fromPhrase(spokenText);

  bool get hasPlayableSound {
    if (!hasSound) return false;
    final file = File(audioPath!);
    return file.existsSync() && file.lengthSync() >= 256;
  }

  AacItem copyWith({
    String? label,
    IconData? icon,
    Color? color,
    String? speak,
    List<AacItem>? children,
    Color? tileColor,
    Color? foregroundColor,
    TtsTone? tone,
    String? customId,
    String? originalLabel,
    String? imagePath,
    String? audioPath,
    bool clearImagePath = false,
    bool clearAudioPath = false,
  }) {
    return AacItem(
      label: label ?? this.label,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      speak: speak ?? this.speak,
      children: children ?? this.children,
      tileColor: tileColor ?? this.tileColor,
      foregroundColor: foregroundColor ?? this.foregroundColor,
      tone: tone ?? this.tone,
      customId: customId ?? this.customId,
      originalLabel: originalLabel ?? this.originalLabel,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      audioPath: clearAudioPath ? null : (audioPath ?? this.audioPath),
    );
  }
}

const _buttonSoundChannel = MethodChannel('swiftspeak/button_sound');
const _silentRecordingPeak = 300;

int? wavPeakAmplitude(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final bytes = file.readAsBytesSync();
  if (bytes.length < 44) return null;
  if (bytes[0] != 0x52 || bytes[1] != 0x49) return null;

  var offset = 12;
  var dataStart = -1;
  var dataSize = 0;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = ByteData.sublistView(bytes, offset + 4, offset + 8)
        .getUint32(0, Endian.little);
    if (id == 'fmt ' && offset + 24 <= bytes.length) {
      final format = ByteData.sublistView(bytes, offset + 8, offset + 24);
      if (format.getUint16(0, Endian.little) != 1) return null;
    } else if (id == 'data') {
      dataStart = offset + 8;
      dataSize = size;
      break;
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  if (dataStart < 0) return null;
  final end = math.min(bytes.length, dataStart + dataSize);
  var peak = 0;
  for (var i = dataStart; i + 1 < end; i += 2) {
    var sample = bytes[i] | (bytes[i + 1] << 8);
    if (sample >= 32768) sample -= 65536;
    final abs = sample.abs();
    if (abs > peak) peak = abs;
  }
  return peak;
}

String? silentRecordingMessage(String path) {
  final peak = wavPeakAmplitude(path);
  if (peak == null) return null;
  if (peak < _silentRecordingPeak) {
    return 'The microphone captured no voice. On the emulator, turn on Microphone and use host audio, or test on a real phone.';
  }
  return null;
}

Future<void> resetButtonSoundAudio() async {
  if (!Platform.isAndroid) return;
  try {
    await _buttonSoundChannel.invokeMethod<void>('resetAudio');
  } catch (_) {}
}

Future<void> stopStoredButtonSound(AudioPlayer player) async {
  if (Platform.isAndroid) {
    try {
      await _buttonSoundChannel.invokeMethod<void>('stop');
    } catch (_) {}
    return;
  }
  await player.stop();
}

Future<String?> playStoredButtonSound(AudioPlayer player, String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    return 'That sound file is missing. Record it again.';
  }
  if (file.lengthSync() < 256) {
    return 'That recording was empty. Check the microphone and try again.';
  }
  final silent = silentRecordingMessage(path);
  if (silent != null) return silent;
  try {
    if (Platform.isAndroid) {
      await _buttonSoundChannel.invokeMethod<void>('play', {'path': file.path});
      return null;
    }
    await player.stop();
    await player.setVolume(1);
    await player.setFilePath(file.path);
    await player.play();
    return null;
  } on MissingPluginException {
    return 'Stop the app and run it again to turn button sounds on.';
  } on PlatformException catch (error) {
    return error.message ?? 'Could not play that sound.';
  } catch (error) {
    return 'Could not play that sound. ${error.toString()}';
  }
}

class AacSearchHit {
  const AacSearchHit({
    required this.item,
    required this.path,
    required this.pageTitle,
    required this.pageItems,
    required this.isHomePage,
  });

  final AacItem item;
  final List<String> path;
  final String pageTitle;
  final List<AacItem> pageItems;
  final bool isHomePage;

  String get location => path.isEmpty ? 'Home' : path.join(' › ');

  String get categoryId {
    if (isHomePage) return 'Home';
    return path.join(' › ');
  }
}

class AacVocabulary {
  static const yes = AacItem(
    label: 'Yes',
    speak: 'Yes',
    icon: Icons.check_circle,
    color: Colors.green,
    tileColor: Color(0xFFE8F5E9),
    tone: TtsTone.affirming,
  );

  static const no = AacItem(
    label: 'No',
    speak: 'No',
    icon: Icons.cancel,
    color: Colors.blueGrey,
    tileColor: Color(0xFFEEEEEE),
    tone: TtsTone.firm,
  );

  static const emergency = AacItem(
    label: 'Emergency',
    speak: 'I need emergency help right now',
    icon: Icons.warning,
    color: Colors.white,
    tileColor: Color(0xFFE53935),
    foregroundColor: Colors.white,
    tone: TtsTone.urgent,
  );

  /// Home content is 16 items so the compact 4x4 layout can fill.
  /// Emergency, Yes, and No stay pinned under the grid.
  static const home = <AacItem>[
    AacItem(
      label: 'Core',
      icon: Icons.grid_view,
      color: Colors.indigo,
      tileColor: Color(0xFFE8EAF6),
      children: coreMenu,
    ),
    AacItem(
      label: 'Topics',
      icon: Icons.category,
      color: Colors.deepPurple,
      tileColor: Color(0xFFEDE7F6),
      children: topicsMenu,
    ),
    AacItem(
      label: 'Feelings',
      icon: Icons.emoji_emotions,
      color: Colors.purple,
      tileColor: Color(0xFFF3E5F5),
      children: feelings,
    ),
    AacItem(
      label: 'Comfort',
      icon: Icons.thermostat,
      color: Colors.teal,
      tileColor: Color(0xFFE0F2F1),
      children: comfort,
    ),
    AacItem(
      label: 'Questions',
      icon: Icons.question_mark,
      color: Colors.indigo,
      tileColor: Color(0xFFE8EAF6),
      children: questions,
    ),
    AacItem(
      label: 'Needs',
      icon: Icons.room_service,
      color: Colors.orange,
      tileColor: Color(0xFFFFF3E0),
      children: needs,
    ),
    AacItem(
      label: 'Pain',
      icon: Icons.healing,
      color: Colors.deepOrange,
      tileColor: Color(0xFFFBE9E7),
      children: pain,
    ),
    AacItem(
      label: 'People',
      icon: Icons.groups,
      color: Colors.pink,
      tileColor: Color(0xFFFCE4EC),
      children: people,
    ),
    AacItem(
      label: 'Symptoms',
      icon: Icons.sick,
      color: Colors.green,
      tileColor: Color(0xFFE8F5E9),
      children: symptoms,
    ),
    AacItem(
      label: 'Care',
      icon: Icons.soap,
      color: Colors.teal,
      tileColor: Color(0xFFE0F7FA),
      children: care,
    ),
    AacItem(
      label: 'Help',
      speak: 'I need help',
      icon: Icons.help,
      color: Colors.amber,
    ),
    AacItem(
      label: 'Bathroom',
      speak: 'I need the bathroom',
      icon: Icons.wc,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Medicine',
      speak: 'I need medication',
      icon: Icons.medication,
      color: Colors.red,
    ),
    AacItem(
      label: 'Hungry',
      speak: "I'm hungry",
      icon: Icons.restaurant,
      color: Colors.orange,
    ),
    AacItem(
      label: 'Thirsty',
      speak: "I'm thirsty",
      icon: Icons.water_drop,
      color: Colors.blue,
    ),
    AacItem(
      label: 'Nurse',
      speak: 'I need a nurse',
      icon: Icons.local_hospital,
      color: Colors.red,
    ),
    AacItem(
      label: 'Stop',
      speak: 'Stop',
      icon: Icons.stop_circle,
      color: Colors.red,
    ),
    AacItem(
      label: 'Thank you',
      speak: 'Thank you',
      icon: Icons.favorite,
      color: Colors.red,
    ),
    emergency,
    yes,
    no,
  ];

  static const basicHome = <AacItem>[
    AacItem(
      label: 'Requests',
      icon: Icons.front_hand,
      color: Colors.amber,
      tileColor: Color(0xFFFFF8E1),
      children: basicRequests,
    ),
    AacItem(
      label: 'Choices / responses',
      icon: Icons.thumbs_up_down,
      color: Colors.green,
      tileColor: Color(0xFFE8F5E9),
      children: basicChoices,
    ),
    AacItem(
      label: 'Actions',
      icon: Icons.directions_run,
      color: Colors.green,
      tileColor: Color(0xFFE8F5E9),
      children: basicActions,
    ),
    AacItem(
      label: 'People / social',
      icon: Icons.groups,
      color: Colors.pink,
      tileColor: Color(0xFFFCE4EC),
      children: basicPeopleSocial,
    ),
    AacItem(
      label: 'Needs / feelings',
      icon: Icons.favorite,
      color: Colors.orange,
      tileColor: Color(0xFFFFF3E0),
      children: basicNeedsFeelings,
    ),
    AacItem(
      label: 'Sentence starters',
      icon: Icons.format_quote,
      color: Colors.indigo,
      tileColor: Color(0xFFE8EAF6),
      children: basicStarters,
    ),
    AacItem(
      label: 'Topic words',
      icon: Icons.category,
      color: Colors.deepPurple,
      tileColor: Color(0xFFEDE7F6),
      children: basicTopicWords,
    ),
    emergency,
    yes,
    no,
  ];

  static List<AacItem> get activeHome {
    return AacAccessController.instance.settings.vocabLevel ==
            AacVocabLevel.basic
        ? basicHome
        : home;
  }

  static const addWordId = '__add_word__';

  static const addWord = AacItem(
    label: 'Add word',
    icon: Icons.add_circle,
    color: Colors.deepPurple,
    tileColor: Color(0xFFF3E5F5),
    customId: addWordId,
  );

  static List<AacItem> homeWithMyWords(List<AacItem> custom) {
    final myWords = AacItem(
      label: 'My words',
      icon: Icons.star,
      color: Colors.deepPurple,
      tileColor: const Color(0xFFF3E5F5),
      children: [...custom, yes, no],
    );
    final items = <AacItem>[];
    var inserted = false;
    for (final item in activeHome) {
      if (!inserted &&
          (item.label == 'Help' || item.identity == emergency.identity)) {
        items.add(myWords);
        inserted = true;
      }
      items.add(item);
    }
    if (!inserted) {
      items.add(myWords);
    }
    return items;
  }

  static List<AacItem> insertCustom(List<AacItem> items, List<AacItem> custom) {
    if (custom.isEmpty) return items;
    final content = items
        .where((item) =>
            item.label != yes.label &&
            item.label != no.label &&
            item.label != emergency.label)
        .toList();
    final pinned = items
        .where((item) =>
            item.label == yes.label ||
            item.label == no.label ||
            item.label == emergency.label)
        .toList();
    return [...content, ...custom, ...pinned];
  }

  static List<AacItem> homeTreeWithCustom() {
    return _withCustomInFolders(
      homeWithMyWords(const []),
      parentId: 'Home',
    );
  }

  static List<AacItem> _withCustomInFolders(
    List<AacItem> items, {
    required String parentId,
  }) {
    final rebuilt = <AacItem>[];
    for (final item in items) {
      if (item.isFolder) {
        final childId = parentId == 'Home'
            ? item.identity
            : '$parentId › ${item.identity}';
        rebuilt.add(
          item.copyWith(
            children: _withCustomInFolders(item.children!, parentId: childId),
          ),
        );
      } else {
        rebuilt.add(item);
      }
    }
    return AacButtonEditController.instance.applyAll(
      insertCustom(
        rebuilt,
        AacCustomWordsController.instance.itemsIn(parentId),
      ),
      parentId,
    );
  }

  static void invalidateSearch() {
    _searchCache = null;
    _searchLevel = null;
  }

  static List<AacSearchHit>? _searchCache;
  static AacVocabLevel? _searchLevel;

  static List<AacSearchHit> get searchIndex {
    final level = AacAccessController.instance.settings.vocabLevel;
    if (_searchCache == null || _searchLevel != level) {
      _searchLevel = level;
      _searchCache = _buildSearchIndex();
    }
    return _searchCache!;
  }

  static List<AacSearchHit> _buildSearchIndex() {
    final hits = <AacSearchHit>[];

    void walk(
      List<AacItem> items,
      List<String> path,
      String pageTitle,
      bool isHome,
    ) {
      for (final item in items) {
        if (item.customId == addWordId) continue;
        final isPinnedRepeat = !isHome &&
            (item.label == yes.label ||
                item.label == no.label ||
                item.label == emergency.label);
        if (!isPinnedRepeat) {
          hits.add(
            AacSearchHit(
              item: item,
              path: path,
              pageTitle: pageTitle,
              pageItems: items,
              isHomePage: isHome,
            ),
          );
        }
        if (item.children != null) {
          walk(
            item.children!,
            [...path, item.identity],
            item.identity,
            false,
          );
        }
      }
    }

    walk(
      homeTreeWithCustom(),
      const [],
      'Communicate',
      true,
    );
    return hits;
  }

  static List<AacSearchHit> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    final ranked = <(int score, AacSearchHit hit)>[];
    for (final hit in searchIndex) {
      final label = hit.item.label.toLowerCase();
      final translated = hit.item.displayLabel.toLowerCase();
      final original = (hit.item.originalLabel ?? '').toLowerCase();
      final speak = (hit.item.speak ?? '').toLowerCase();
      final location = hit.location.toLowerCase();
      int? score;
      if (label == needle || original == needle || translated == needle) {
        score = 0;
      } else if (label.startsWith(needle) ||
          original.startsWith(needle) ||
          translated.startsWith(needle)) {
        score = 1;
      } else if (label.contains(needle) ||
          original.contains(needle) ||
          translated.contains(needle)) {
        score = 2;
      } else if (speak.startsWith(needle)) {
        score = 3;
      } else if (speak.contains(needle)) {
        score = 4;
      } else if (location.contains(needle)) {
        score = 5;
      }
      if (score != null) {
        ranked.add((score, hit));
      }
    }

    ranked.sort((a, b) {
      final byScore = a.$1.compareTo(b.$1);
      if (byScore != 0) return byScore;
      return a.$2.item.label.toLowerCase().compareTo(b.$2.item.label.toLowerCase());
    });
    return ranked.take(40).map((entry) => entry.$2).toList();
  }

  static const pain = <AacItem>[
    AacItem(
      label: 'It hurts',
      speak: 'It hurts',
      icon: Icons.priority_high,
      color: Colors.deepOrange,
    ),
    AacItem(
      label: 'Pain meds',
      speak: 'I need pain medication',
      icon: Icons.medication,
      color: Colors.red,
    ),
    AacItem(
      label: 'Worse',
      speak: 'The pain is worse',
      icon: Icons.arrow_upward,
      color: Colors.red,
    ),
    AacItem(
      label: 'Better',
      speak: 'The pain is better',
      icon: Icons.arrow_downward,
      color: Colors.green,
    ),
    AacItem(
      label: 'Head',
      speak: 'I have head pain',
      icon: Icons.face,
      color: Colors.deepOrange,
    ),
    AacItem(
      label: 'Chest',
      speak: 'I have chest pain',
      icon: Icons.favorite,
      color: Colors.red,
    ),
    AacItem(
      label: 'Stomach',
      speak: 'I have stomach pain',
      icon: Icons.airline_seat_flat,
      color: Colors.orange,
    ),
    AacItem(
      label: 'Back',
      speak: 'I have back pain',
      icon: Icons.accessibility_new,
      color: Colors.brown,
    ),
    AacItem(
      label: 'Neck',
      speak: 'I have neck pain',
      icon: Icons.accessibility,
      color: Colors.deepOrange,
    ),
    AacItem(
      label: 'Arm',
      speak: 'I have arm pain',
      icon: Icons.back_hand,
      color: Colors.brown,
    ),
    AacItem(
      label: 'Leg',
      speak: 'I have leg pain',
      icon: Icons.directions_walk,
      color: Colors.teal,
    ),
    AacItem(
      label: 'Throat',
      speak: 'I have a sore throat',
      icon: Icons.record_voice_over,
      color: Colors.pink,
    ),
    AacItem(
      label: 'Here',
      speak: 'The pain is here',
      icon: Icons.touch_app,
      color: Colors.deepOrange,
    ),
    AacItem(
      label: 'Sharp',
      speak: 'The pain is sharp',
      icon: Icons.bolt,
      color: Colors.amber,
    ),
    AacItem(
      label: 'Dull',
      speak: 'The pain is a dull ache',
      icon: Icons.circle,
      color: Colors.blueGrey,
    ),
    AacItem(
      label: 'Burning',
      speak: 'The pain is burning',
      icon: Icons.local_fire_department,
      color: Colors.deepOrange,
    ),
    AacItem(
      label: 'Throbbing',
      speak: 'The pain is throbbing',
      icon: Icons.graphic_eq,
      color: Colors.purple,
    ),
    AacItem(
      label: 'Stabbing',
      speak: 'The pain is stabbing',
      icon: Icons.square,
      color: Colors.red,
    ),
    AacItem(
      label: 'All over',
      speak: 'The pain is all over',
      icon: Icons.language,
      color: Colors.indigo,
    ),
    yes,
    no,
  ];

  static const needs = <AacItem>[
    AacItem(
      label: 'Bathroom',
      speak: 'I need the bathroom',
      icon: Icons.wc,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Hungry',
      speak: "I'm hungry",
      icon: Icons.restaurant,
      color: Colors.orange,
    ),
    AacItem(
      label: 'Thirsty',
      speak: "I'm thirsty",
      icon: Icons.water_drop,
      color: Colors.blue,
    ),
    AacItem(
      label: 'Medicine',
      speak: 'I need medication',
      icon: Icons.medication,
      color: Colors.red,
    ),
    AacItem(
      label: 'Ice chips',
      speak: 'I need ice chips',
      icon: Icons.severe_cold,
      color: Colors.lightBlue,
    ),
    AacItem(
      label: 'Water',
      speak: 'I need water',
      icon: Icons.local_drink,
      color: Colors.blue,
    ),
    AacItem(
      label: 'Snack',
      speak: 'I want a snack',
      icon: Icons.cookie,
      color: Colors.brown,
    ),
    AacItem(
      label: 'Rest',
      speak: 'I want to rest',
      icon: Icons.hotel,
      color: Colors.blueGrey,
    ),
    AacItem(
      label: 'Toilet help',
      speak: 'I need help getting to the bathroom',
      icon: Icons.accessible,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Bedpan',
      speak: 'I need a bedpan',
      icon: Icons.airline_seat_flat,
      color: Colors.blueGrey,
    ),
    AacItem(
      label: 'Not hungry',
      speak: "I'm not hungry",
      icon: Icons.no_meals,
      color: Colors.orange,
    ),
    AacItem(
      label: 'More water',
      speak: 'I need more water',
      icon: Icons.opacity,
      color: Colors.lightBlue,
    ),
    yes,
    no,
  ];

  static const care = <AacItem>[
    AacItem(
      label: 'Toothbrush',
      speak: 'I need to brush my teeth',
      icon: Icons.cleaning_services,
      color: Colors.teal,
    ),
    AacItem(
      label: 'Wash up',
      speak: 'I need to wash up',
      icon: Icons.soap,
      color: Colors.lightBlue,
    ),
    AacItem(
      label: 'Clothes',
      speak: 'I need a change of clothes',
      icon: Icons.checkroom,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Tissue',
      speak: 'I need a tissue',
      icon: Icons.dry,
      color: Colors.blueGrey,
    ),
    AacItem(
      label: 'Glasses',
      speak: 'I need my glasses',
      icon: Icons.visibility,
      color: Colors.blue,
    ),
    AacItem(
      label: 'Hearing aid',
      speak: 'I need my hearing aid',
      icon: Icons.hearing,
      color: Colors.purple,
    ),
    AacItem(
      label: 'Phone',
      speak: 'I need my phone',
      icon: Icons.smartphone,
      color: Colors.green,
    ),
    AacItem(
      label: 'Charger',
      speak: 'I need a charger',
      icon: Icons.battery_charging_full,
      color: Colors.amber,
    ),
    AacItem(
      label: 'Lip balm',
      speak: 'I need lip balm',
      icon: Icons.spa,
      color: Colors.pink,
    ),
    yes,
    no,
  ];

  static const symptoms = <AacItem>[
    AacItem(
      label: "Can't breathe",
      speak: "I can't breathe",
      icon: Icons.air,
      color: Colors.lightBlue,
    ),
    AacItem(
      label: 'Allergic',
      speak: 'I am having an allergic reaction',
      icon: Icons.warning_amber,
      color: Colors.orange,
    ),
    AacItem(
      label: 'Nauseous',
      speak: 'I feel nauseous',
      icon: Icons.sick,
      color: Colors.green,
    ),
    AacItem(
      label: 'Dizzy',
      speak: 'I feel dizzy',
      icon: Icons.sync,
      color: Colors.purple,
    ),
    AacItem(
      label: 'Cough',
      speak: 'I need to cough',
      icon: Icons.health_and_safety,
      color: Colors.blueGrey,
    ),
    AacItem(
      label: 'Itch',
      speak: 'I am itchy',
      icon: Icons.front_hand,
      color: Colors.brown,
    ),
    AacItem(
      label: 'Weak',
      speak: 'I feel weak',
      icon: Icons.battery_alert,
      color: Colors.red,
    ),
    AacItem(
      label: 'Fever',
      speak: 'I think I have a fever',
      icon: Icons.thermostat,
      color: Colors.deepOrange,
    ),
    AacItem(
      label: "Can't swallow",
      speak: "I can't swallow",
      icon: Icons.no_drinks,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Numb',
      speak: 'I feel numb',
      icon: Icons.back_hand,
      color: Colors.blueGrey,
    ),
    yes,
    no,
  ];

  static const comfort = <AacItem>[
    AacItem(
      label: 'cold',
      icon: Icons.ac_unit,
      color: Colors.lightBlue,
    ),
    AacItem(
      label: 'hot',
      icon: Icons.wb_sunny,
      color: Colors.orange,
    ),
    AacItem(
      label: 'Uncomfortable',
      speak: "I'm uncomfortable",
      icon: Icons.sentiment_dissatisfied,
      color: Colors.brown,
    ),
    AacItem(
      label: 'Tired',
      speak: "I'm tired",
      icon: Icons.bedtime,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Sit up',
      speak: 'Please sit me up',
      icon: Icons.airline_seat_recline_normal,
      color: Colors.teal,
    ),
    AacItem(
      label: 'Lie down',
      speak: 'Please lay me down',
      icon: Icons.airline_seat_flat,
      color: Colors.teal,
    ),
    AacItem(
      label: 'Reposition',
      speak: 'Please change my position',
      icon: Icons.screen_rotation,
      color: Colors.teal,
    ),
    AacItem(
      label: 'Blanket',
      speak: 'I need a blanket',
      icon: Icons.bedroom_parent,
      color: Colors.lightBlue,
    ),
    AacItem(
      label: 'Too bright',
      speak: "It's too bright",
      icon: Icons.wb_incandescent,
      color: Colors.amber,
    ),
    AacItem(
      label: 'Too loud',
      speak: "It's too loud",
      icon: Icons.volume_up,
      color: Colors.deepPurple,
    ),
    AacItem(
      label: 'Pillow',
      speak: 'I need another pillow',
      icon: Icons.bedroom_child,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Fan',
      speak: 'Please turn on a fan',
      icon: Icons.cyclone,
      color: Colors.lightBlue,
    ),
    AacItem(
      label: 'Window',
      speak: 'Please open the window',
      icon: Icons.window,
      color: Colors.teal,
    ),
    AacItem(
      label: 'Darker',
      speak: 'Please make it darker',
      icon: Icons.dark_mode,
      color: Colors.blueGrey,
    ),
    AacItem(
      label: 'Quieter',
      speak: 'Please make it quieter',
      icon: Icons.volume_off,
      color: Colors.deepPurple,
    ),
    AacItem(
      label: 'TV off',
      speak: 'Please turn the TV off',
      icon: Icons.tv_off,
      color: Colors.brown,
    ),
    AacItem(
      label: 'Socks',
      speak: 'I need socks',
      icon: Icons.snowshoeing,
      color: Colors.blue,
    ),
    AacItem(
      label: 'Door',
      speak: 'Please close the door',
      icon: Icons.door_front_door,
      color: Colors.brown,
    ),
    AacItem(
      label: 'Remote',
      speak: 'I need the remote',
      icon: Icons.settings_remote,
      color: Colors.grey,
    ),
    yes,
    no,
  ];

  static const feelings = <AacItem>[
    AacItem(
      label: 'okay',
      icon: Icons.sentiment_satisfied,
      color: Colors.green,
    ),
    AacItem(
      label: 'happy',
      icon: Icons.sentiment_very_satisfied,
      color: Colors.amber,
    ),
    AacItem(
      label: 'sad',
      icon: Icons.sentiment_dissatisfied,
      color: Colors.blue,
    ),
    AacItem(
      label: 'scared',
      icon: Icons.report,
      color: Colors.deepOrange,
    ),
    AacItem(
      label: 'anxious',
      icon: Icons.psychology,
      color: Colors.purple,
    ),
    AacItem(
      label: 'angry',
      icon: Icons.mood_bad,
      color: Colors.red,
    ),
    AacItem(
      label: 'frustrated',
      icon: Icons.sentiment_very_dissatisfied,
      color: Colors.deepOrange,
    ),
    AacItem(
      label: 'confused',
      icon: Icons.help_outline,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'overwhelmed',
      icon: Icons.waves,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'lonely',
      icon: Icons.person_off,
      color: Colors.blueGrey,
    ),
    AacItem(
      label: 'worried',
      icon: Icons.sentiment_neutral,
      color: Colors.orange,
    ),
    AacItem(
      label: 'bored',
      icon: Icons.hourglass_empty,
      color: Colors.brown,
    ),
    AacItem(
      label: 'embarrassed',
      icon: Icons.face,
      color: Colors.pink,
    ),
    AacItem(
      label: 'hopeful',
      icon: Icons.wb_sunny,
      color: Colors.amber,
    ),
    AacItem(
      label: 'sorry',
      icon: Icons.handshake,
      color: Colors.blue,
    ),
    AacItem(
      label: 'love',
      icon: Icons.favorite,
      color: Colors.red,
    ),
    AacItem(
      label: 'grateful',
      icon: Icons.volunteer_activism,
      color: Colors.pink,
    ),
    AacItem(
      label: 'fed up',
      icon: Icons.heart_broken,
      color: Colors.deepOrange,
    ),
    AacItem(
      label: 'proud',
      icon: Icons.emoji_events,
      color: Colors.amber,
    ),
    yes,
    no,
  ];

  static const people = <AacItem>[
    AacItem(
      label: 'Nurse',
      speak: 'I need a nurse',
      icon: Icons.local_hospital,
      color: Colors.red,
    ),
    AacItem(
      label: 'Doctor',
      speak: 'I need a doctor',
      icon: Icons.medical_services,
      color: Colors.blue,
    ),
    AacItem(
      label: 'Thank you',
      speak: 'Thank you',
      icon: Icons.favorite,
      color: Colors.red,
    ),
    AacItem(
      label: 'Please',
      speak: 'Please',
      icon: Icons.front_hand,
      color: Colors.orange,
    ),
    AacItem(
      label: 'Family',
      speak: 'I want my family',
      icon: Icons.family_restroom,
      color: Colors.pink,
    ),
    AacItem(
      label: 'Call family',
      speak: 'Please call my family',
      icon: Icons.call,
      color: Colors.pink,
    ),
    AacItem(
      label: 'Visitor',
      speak: 'I want a visitor',
      icon: Icons.groups,
      color: Colors.teal,
    ),
    AacItem(
      label: 'Alone',
      speak: 'I want to be alone',
      icon: Icons.person,
      color: Colors.blueGrey,
    ),
    AacItem(
      label: 'Therapy',
      speak: 'I need therapy',
      icon: Icons.self_improvement,
      color: Colors.green,
    ),
    AacItem(
      label: 'Interpreter',
      speak: 'I need an interpreter',
      icon: Icons.translate,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Friend',
      speak: 'I want my friend',
      icon: Icons.people,
      color: Colors.teal,
    ),
    AacItem(
      label: 'Chaplain',
      speak: 'I would like a chaplain',
      icon: Icons.church,
      color: Colors.purple,
    ),
    AacItem(
      label: 'Come here',
      speak: 'Please come here',
      icon: Icons.waving_hand,
      color: Colors.orange,
    ),
    AacItem(
      label: "Don't leave",
      speak: "Please don't leave",
      icon: Icons.front_hand,
      color: Colors.red,
    ),
    AacItem(
      label: 'Hold hand',
      speak: 'Please hold my hand',
      icon: Icons.handshake,
      color: Colors.pink,
    ),
    AacItem(
      label: 'Speak slower',
      speak: 'Please speak slower',
      icon: Icons.slow_motion_video,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Look at me',
      speak: 'Please look at me',
      icon: Icons.visibility,
      color: Colors.blue,
    ),
    AacItem(
      label: 'Social work',
      speak: 'I need a social worker',
      icon: Icons.support,
      color: Colors.green,
    ),
    AacItem(
      label: 'Privacy',
      speak: 'I need privacy',
      icon: Icons.privacy_tip,
      color: Colors.blueGrey,
    ),
    yes,
    no,
  ];

  static const questions = <AacItem>[
    AacItem(
      label: 'Question',
      speak: 'I have a question',
      icon: Icons.question_mark,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Explain',
      speak: 'Please explain',
      icon: Icons.info,
      color: Colors.blue,
    ),
    AacItem(
      label: 'Repeat',
      speak: 'Please repeat that',
      icon: Icons.replay,
      color: Colors.teal,
    ),
    AacItem(
      label: "Don't get it",
      speak: "I don't understand",
      icon: Icons.hearing_disabled,
      color: Colors.blueGrey,
    ),
    AacItem(
      label: 'Wait',
      speak: 'Please wait',
      icon: Icons.pause_circle,
      color: Colors.orange,
    ),
    AacItem(
      label: 'Stop',
      speak: 'Stop',
      icon: Icons.stop_circle,
      color: Colors.red,
    ),
    AacItem(
      label: 'Write it',
      speak: 'Please write that down',
      icon: Icons.edit,
      color: Colors.blue,
    ),
    AacItem(
      label: 'What next?',
      speak: 'What happens next?',
      icon: Icons.skip_next,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'Leave',
      speak: 'When can I leave?',
      icon: Icons.logout,
      color: Colors.brown,
    ),
    AacItem(
      label: 'How long?',
      speak: 'How long will this take?',
      icon: Icons.schedule,
      color: Colors.indigo,
    ),
    AacItem(
      label: 'What time?',
      speak: 'What time is it?',
      icon: Icons.access_time,
      color: Colors.blue,
    ),
    AacItem(
      label: 'Go home?',
      speak: 'Can I go home?',
      icon: Icons.home,
      color: Colors.green,
    ),
    AacItem(
      label: 'This med?',
      speak: 'What is this medication?',
      icon: Icons.medication_liquid,
      color: Colors.red,
    ),
    AacItem(
      label: 'Why?',
      speak: 'Why is this happening?',
      icon: Icons.help_center,
      color: Colors.deepOrange,
    ),
    AacItem(
      label: 'Who are you?',
      speak: 'Who are you?',
      icon: Icons.badge,
      color: Colors.teal,
    ),
    AacItem(
      label: 'Serious?',
      speak: 'Is it serious?',
      icon: Icons.priority_high,
      color: Colors.red,
    ),
    AacItem(
      label: 'Show me',
      speak: 'Please show me',
      icon: Icons.preview,
      color: Colors.purple,
    ),
    AacItem(
      label: 'Break',
      speak: 'I need a break',
      icon: Icons.free_breakfast,
      color: Colors.brown,
    ),
    AacItem(
      label: 'Call someone',
      speak: 'Please call someone for me',
      icon: Icons.phone_in_talk,
      color: Colors.green,
    ),
    yes,
    no,
  ];
}

class AacMessageController extends ChangeNotifier {
  AacMessageController._() {
    textController.addListener(notifyListeners);
  }

  static final AacMessageController instance = AacMessageController._();

  final TextEditingController textController = TextEditingController();
  final SpeechToText _speech = SpeechToText();

  bool isListening = false;
  String? errorMessage;
  bool _ready = false;
  String _textBeforeListen = '';

  void append(String phrase) {
    final addition = phrase.trim();
    if (addition.isEmpty) return;
    final current = textController.text.trimRight();
    final next = current.isEmpty ? addition : '$current $addition';
    textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    TypingPredictionStore.instance.learnFromTyping(
      '$next ',
      surface: 'communication',
    );
    notifyListeners();
  }

  void insertText(String value) {
    if (value.isEmpty) return;
    final text = textController.text;
    var start = textController.selection.start;
    var end = textController.selection.end;
    if (!textController.selection.isValid) {
      start = text.length;
      end = text.length;
    }
    start = start.clamp(0, text.length);
    end = end.clamp(0, text.length);
    if (start > end) {
      final swap = start;
      start = end;
      end = swap;
    }
    final next = text.replaceRange(start, end, value);
    textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    notifyListeners();
  }

  void backspace() {
    final text = textController.text;
    if (text.isEmpty) return;
    var start = textController.selection.start;
    var end = textController.selection.end;
    if (!textController.selection.isValid) {
      start = text.length;
      end = text.length;
    }
    start = start.clamp(0, text.length);
    end = end.clamp(0, text.length);
    if (start > end) {
      final swap = start;
      start = end;
      end = swap;
    }
    if (start != end) {
      final next = text.replaceRange(start, end, '');
      textController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start),
      );
    } else if (start > 0) {
      final next = text.replaceRange(start - 1, start, '');
      textController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      return;
    }
    notifyListeners();
  }

  void clear() {
    textController.clear();
    errorMessage = null;
    notifyListeners();
  }

  Future<void> toggleListen() async {
    errorMessage = null;
    if (isListening || _speech.isListening) {
      await _speech.stop();
      isListening = false;
      notifyListeners();
      return;
    }

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      errorMessage = micStatus.isPermanentlyDenied
          ? 'Enable the microphone in system settings, then try again.'
          : 'Microphone permission is required to turn speech into text.';
      notifyListeners();
      if (micStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
      return;
    }

    if (!_ready) {
      _ready = await _speech.initialize(
        onStatus: (status) {
          if (status == SpeechToText.listeningStatus) {
            isListening = true;
            notifyListeners();
            return;
          }
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            isListening = false;
            notifyListeners();
          }
        },
        onError: (error) {
          isListening = false;
          errorMessage = _friendlySpeechError(error.errorMsg);
          notifyListeners();
        },
      );
    }

    if (!_ready) {
      errorMessage =
          'Speech-to-text is not available. Use a real phone with internet, and allow microphone access.';
      notifyListeners();
      return;
    }

    // Let TTS finish releasing the audio session before the mic opens.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    _textBeforeListen = textController.text.trimRight();
    isListening = true;
    notifyListeners();

    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          final next = _textBeforeListen.isEmpty
              ? words
              : words.isEmpty
                  ? _textBeforeListen
                  : '$_textBeforeListen $words';
          textController.value = TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: next.length),
          );
          notifyListeners();
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 8),
        ),
      );
    } catch (error) {
      isListening = false;
      errorMessage = 'Could not start the microphone. Try again.';
      notifyListeners();
      return;
    }

    if (!_speech.isListening) {
      isListening = false;
      errorMessage ??=
          'Could not start listening. Check the microphone and try on a real phone.';
      notifyListeners();
    }
  }

  static String _friendlySpeechError(String code) {
    switch (code) {
      case 'error_permission':
      case 'error_insufficient_permissions':
        return 'Microphone permission is required. Check app settings.';
      case 'error_audio':
      case 'error_audio_error':
        return 'Could not use the microphone. Stop other audio and try again.';
      case 'error_network':
      case 'error_network_timeout':
        return 'Speech-to-text needs an internet connection.';
      case 'error_speech_timeout':
      case 'error_no_match':
        return 'No speech heard. Tap the mic and speak clearly.';
      case 'error_busy':
      case 'error_recognizer_busy':
        return 'Speech recognition is busy. Wait a moment and try again.';
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return 'This language is not available for speech-to-text on this device.';
      case 'error_speech_recognizer_disabled':
        return 'Speech recognition is turned off in system settings.';
      default:
        return 'Could not hear speech. Tap the mic and try again.';
    }
  }
}

class AacBoardPage extends StatefulWidget {
  const AacBoardPage({
    super.key,
    required this.title,
    required this.items,
    this.isHome = false,
    this.highlightLabel,
    this.categoryId,
  });

  final String title;
  final List<AacItem> items;
  final bool isHome;
  final String? highlightLabel;
  final String? categoryId;

  @override
  State<AacBoardPage> createState() => _AacBoardPageState();
}

class _AacBoardPageState extends State<AacBoardPage> {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  late final PageController _pageController;
  final Map<String, GlobalKey> _tileKeys = {};
  int _pageIndex = 0;
  int? _activePointer;
  AacItem? _armedItem;
  DateTime? _armedSince;
  Timer? _holdTimer;
  Timer? _highlightTimer;
  Timer? _predictTimer;
  double _holdProgress = 0;
  String? _highlightLabel;
  Set<String> _predictedIds = {};
  List<String> _phraseSuggestions = [];
  int _predictToken = 0;

  @override
  void initState() {
    super.initState();
    _highlightLabel = widget.highlightLabel;
    _pageIndex = _pageIndexForLabel(_highlightLabel);
    _pageController = PageController(initialPage: _pageIndex);
    _setupTts();
    _startHighlightTimer();
    AacMessageController.instance.addListener(_onPredictSourceChanged);
    AacAccessController.instance.addListener(_onPredictSourceChanged);
    AacCustomWordsController.instance.addListener(_onPredictSourceChanged);
    AacButtonEditController.instance.addListener(_onPredictSourceChanged);
    unawaited(TypingPredictionStore.instance.start());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runPredict();
    });
  }

  Future<void> _setupTts() async {
    await _flutterTts.setLanguage(AppLanguage.instance.ttsLanguage);
    await _flutterTts.awaitSpeakCompletion(true);
    try {
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
      );
    } catch (_) {
      // Android and other platforms ignore this iOS-only setting.
    }
    await _applyTone(TtsTone.neutral);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _highlightTimer?.cancel();
    _predictTimer?.cancel();
    AacMessageController.instance.removeListener(_onPredictSourceChanged);
    AacAccessController.instance.removeListener(_onPredictSourceChanged);
    AacCustomWordsController.instance.removeListener(_onPredictSourceChanged);
    AacButtonEditController.instance.removeListener(_onPredictSourceChanged);
    _pageController.dispose();
    _flutterTts.stop();
    stopStoredButtonSound(_audioPlayer);
    _audioPlayer.dispose();
    super.dispose();
  }

  int _pageIndexForLabel(String? label) {
    if (label == null || label.isEmpty) return 0;
    final perPage = AacAccessController.instance.settings.buttonsPerPage;
    final index = _contentItems.indexWhere(
      (item) => item.label.toLowerCase() == label.toLowerCase(),
    );
    if (index < 0) return 0;
    return index ~/ perPage;
  }

  void _startHighlightTimer() {
    _highlightTimer?.cancel();
    if (_highlightLabel == null) return;
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _highlightLabel = null);
    });
  }

  void _focusLabel(String label) {
    final page = _pageIndexForLabel(label);
    if (_pageController.hasClients && page != _pageIndex) {
      _pageController.jumpToPage(page);
    }
    setState(() {
      _pageIndex = page;
      _highlightLabel = label;
    });
    _startHighlightTimer();
  }

  void _onPredictSourceChanged() => _schedulePredict();

  void _schedulePredict() {
    _predictTimer?.cancel();
    _predictTimer = Timer(const Duration(milliseconds: 250), _runPredict);
  }

  List<AacItem> get _visiblePredictItems {
    final settings = AacAccessController.instance.settings;
    final perPage = settings.buttonsPerPage;
    final start = (_pageIndex * perPage).clamp(0, 1 << 20);
    final slice = _contentItems.skip(start).take(perPage);
    return [
      ...slice,
      if (widget.isHome) AacVocabulary.emergency,
      AacVocabulary.yes,
      AacVocabulary.no,
    ].where((item) => !item.isAddWord).toList();
  }

  bool _isPredicted(AacItem item) => _predictedIds.contains(item.identity);

  bool _isDimmed(AacItem item) {
    if (_predictedIds.isEmpty ||
        AacButtonEditController.instance.editing ||
        _highlightLabel != null ||
        _armedItem?.identity == item.identity) {
      return false;
    }
    return !_isPredicted(item);
  }

  Set<String> _matchPredictedLabels(
    Iterable<String> labels,
    List<AacItem> items,
  ) {
    final byKey = <String, AacItem>{};
    for (final item in items) {
      byKey[item.label.toLowerCase().trim()] = item;
      byKey[item.identity.toLowerCase().trim()] = item;
    }
    final matched = <String>{};
    for (final label in labels) {
      final item = byKey[label.toLowerCase().trim()];
      if (item == null) continue;
      matched.add(item.identity);
      if (matched.length >= 2) break;
    }
    return matched;
  }

  Set<String> _heuristicPredict(String message, List<AacItem> items) {
    final text = message.trim().toLowerCase();
    final last = text.isEmpty
        ? ''
        : text
            .split(RegExp(r'\s+'))
            .last
            .replaceAll(RegExp(r"[^a-z']"), '')
            .replaceAll("'m", '')
            .replaceAll("'re", '')
            .replaceAll("'s", '');
    const nextByLast = <String, List<String>>{
      '': [
        'I',
        'want',
        'need',
        'help',
        'Emergency',
        'Pain',
        'Hungry',
        'Requests',
        'Sentence starters',
        'Core',
        'Yes',
      ],
      'i': [
        'want',
        'need',
        'feel',
        'am',
        'like',
        'hurt',
        'Needs',
        'Feelings',
        'Pain',
      ],
      'want': [
        'water',
        'help',
        'food',
        'Bathroom',
        'more',
        'Needs',
        'Hungry',
        'Thirsty',
      ],
      'need': [
        'help',
        'Bathroom',
        'water',
        'Medicine',
        'rest',
        'Needs',
        'Care',
      ],
      'feel': ['Pain', 'sick', 'tired', 'good', 'bad', 'hot', 'cold', 'Feelings'],
      'am': ['tired', 'hot', 'cold', 'in pain', 'ok', 'Feelings'],
      'help': ['me', 'please', 'Bathroom', 'Pain', 'Emergency'],
      'more': ['water', 'help', 'Pain', 'food', 'please'],
      'pain': ['head', 'stomach', 'back', 'more', 'Pain'],
      'my': ['head', 'stomach', 'back', 'throat', 'Pain'],
      'go': ['Bathroom', 'home', 'outside'],
      'eat': ['more', 'food', 'Hungry'],
      'drink': ['water', 'Thirsty', 'more'],
    };
    var wanted = nextByLast[last];
    if (wanted == null && text.endsWith('?')) {
      wanted = ['Yes', 'No'];
    }
    wanted ??= ['Yes', 'No', 'more', 'help'];
    return _matchPredictedLabels(wanted, items);
  }

  Future<void> _runPredict() async {
    if (!mounted) return;
    if (AacButtonEditController.instance.editing) {
      if (_predictedIds.isNotEmpty || _phraseSuggestions.isNotEmpty) {
        setState(() {
          _predictedIds = {};
          _phraseSuggestions = [];
        });
      }
      return;
    }

    final items = _visiblePredictItems;
    if (items.isEmpty) return;
    final message = AacMessageController.instance.textController.text;
    final local = _heuristicPredict(message, items);
    final localPhrases = TypingPredictionStore.instance.localSuggestions(
      message,
      surface: 'communication',
    );
    if ((local.isNotEmpty && !_sameIds(local, _predictedIds)) ||
        !_sameSuggestions(localPhrases, _phraseSuggestions)) {
      setState(() {
        if (local.isNotEmpty) _predictedIds = local;
        _phraseSuggestions = localPhrases;
      });
    }

    final token = ++_predictToken;
    try {
      final results = await Future.wait([
        AiChatService().predictNextAacButtons(
          currentMessage: message,
          buttonLabels: items.map((item) => item.label).toList(),
          personProfile: TypingPredictionStore.instance.surveyPrompt,
        ),
        AiChatService().predictTypingSuggestions(
          currentText: message,
          surface: 'communication',
          learnedHints: TypingPredictionStore.instance.learnedHints(),
          personProfile: TypingPredictionStore.instance.surveyPrompt,
        ),
      ]);
      if (!mounted || token != _predictToken) return;
      final matched = _matchPredictedLabels(results[0], items);
      final phrases = <String>[];
      for (final phrase in [...results[1], ...localPhrases]) {
        if (phrases.any((item) => item.toLowerCase() == phrase.toLowerCase())) {
          continue;
        }
        phrases.add(phrase);
        if (phrases.length >= 6) break;
      }
      setState(() {
        if (matched.isNotEmpty) _predictedIds = matched;
        if (phrases.isNotEmpty) _phraseSuggestions = phrases;
      });
    } catch (_) {
      // Keep the local guess if the AI call fails.
    }
  }

  bool _sameSuggestions(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _acceptPhrase(String phrase) {
    TypingPredictionStore.instance.learnAccepted(
      AacMessageController.instance.textController.text.trim(),
      phrase,
    );
    AacMessageController.instance.append(phrase);
  }

  bool _sameIds(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  GlobalKey _tileKey(AacItem item) {
    return _tileKeys.putIfAbsent(item.identity, GlobalKey.new);
  }

  AacItem? _itemAt(Offset globalPosition) {
    for (final entry in _tileKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final local = box.globalToLocal(globalPosition);
      if (local.dx >= 0 &&
          local.dy >= 0 &&
          local.dx <= box.size.width &&
          local.dy <= box.size.height) {
        return _itemForLabel(entry.key);
      }
    }
    return null;
  }

  AacItem? _itemForLabel(String label) {
    for (final item in _boardItems) {
      if (item.label == label ||
          item.customId == label ||
          item.originalLabel == label ||
          item.identity == label) {
        return item;
      }
    }
    if (label == AacVocabulary.emergency.label) return AacVocabulary.emergency;
    if (label == AacVocabulary.yes.label) return AacVocabulary.yes;
    if (label == AacVocabulary.no.label) return AacVocabulary.no;
    return null;
  }

  void _clearArm({bool keepPointer = false}) {
    _holdTimer?.cancel();
    _holdTimer = null;
    _armedItem = null;
    _armedSince = null;
    _holdProgress = 0;
    if (!keepPointer) {
      _activePointer = null;
    }
    if (mounted) setState(() {});
  }

  void _armAt(Offset globalPosition) {
    final settings = AacAccessController.instance.settings;
    final item = _itemAt(globalPosition);
    if (item == _armedItem) return;

    _holdTimer?.cancel();
    _armedItem = item;
    _armedSince = DateTime.now();
    _holdProgress = 0;
    setState(() {});

    if (item == null) return;

    final hold = settings.holdDurationSeconds;
    if (hold <= 0) {
      if (!settings.selectOnRelease) {
        _onItemTap(item);
        _clearArm(keepPointer: true);
      }
      return;
    }

    _holdTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || _armedItem != item) {
        timer.cancel();
        return;
      }
      final elapsed =
          DateTime.now().difference(_armedSince!).inMilliseconds / 1000.0;
      final progress = (elapsed / hold).clamp(0.0, 1.0);
      setState(() => _holdProgress = progress);
      if (progress >= 1) {
        timer.cancel();
        if (!settings.selectOnRelease) {
          _onItemTap(item);
          _clearArm(keepPointer: true);
        }
      }
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _armAt(event.position);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _armAt(event.position);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    final settings = AacAccessController.instance.settings;
    final item = _armedItem;
    final holdMet =
        settings.holdDurationSeconds <= 0 || _holdProgress >= 1;
    if (settings.selectOnRelease && item != null && holdMet) {
      _onItemTap(item);
    }
    _clearArm();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _clearArm();
  }

  Future<void> _applyTone(TtsTone tone) async {
    await _flutterTts.setPitch(tone.pitch);
    await _flutterTts.setSpeechRate(tone.rate);
    await _flutterTts.setVolume(tone.volume);
  }

  Future<void> _speak(AacItem item) async {
    final phrase = item.spokenText;
    final tone = item.effectiveTone;
    if (AacMessageController.instance.isListening) {
      await AacMessageController.instance.toggleListen();
    }
    await _flutterTts.stop();
    await stopStoredButtonSound(_audioPlayer);
    if (tone == TtsTone.urgent) {
      await HapticFeedback.heavyImpact();
    }
    if (item.hasPlayableSound) {
      final playError =
          await playStoredButtonSound(_audioPlayer, item.audioPath!);
      if (playError == null) return;
    }
    await _applyTone(tone);
    await _flutterTts.speak(phrase);
  }

  void _onItemTap(AacItem item) {
    if (item.isAddWord) {
      _openAddWord();
      return;
    }
    if (AacButtonEditController.instance.editing) {
      _openEditButton(item);
      return;
    }
    if (item.isFolder) {
      final childId = widget.isHome
          ? item.identity
          : '$_categoryId › ${item.identity}';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AacBoardPage(
            title: item.label,
            items: item.children!,
            categoryId: childId,
          ),
        ),
      );
      return;
    }

    _speak(item);
    AacMessageController.instance.append(item.spokenText);
  }

  Future<void> _openEditButton(AacItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _AacEditButtonSheet(
            item: item,
            categoryId: _categoryId,
          ),
        );
      },
    );
  }

  Future<void> _openAddWord() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _AacAddWordSheet(initialCategoryId: _categoryId),
        );
      },
    );
  }

  Future<void> _openWordSearch() async {
    final hit = await showModalBottomSheet<AacSearchHit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: const _AacSearchSheet(),
        );
      },
    );
    if (!mounted || hit == null) return;
    _openSearchHit(hit);
  }

  void _openSearchHit(AacSearchHit hit) {
    if (hit.item.isFolder) {
      final folderId = hit.path.isEmpty
          ? hit.item.identity
          : '${hit.path.join(' › ')} › ${hit.item.identity}';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AacBoardPage(
            title: hit.item.label,
            items: hit.item.children!,
            categoryId: folderId,
          ),
        ),
      );
      return;
    }

    if (widget.title == hit.pageTitle && _categoryId == hit.categoryId) {
      _focusLabel(hit.item.label);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AacBoardPage(
          title: hit.pageTitle,
          items: hit.pageItems,
          isHome: hit.isHomePage,
          highlightLabel: hit.item.label,
          categoryId: hit.categoryId,
        ),
      ),
    );
  }

  bool _isPinned(AacItem item) {
    final id = item.identity;
    if (id == 'Yes' || id == 'No') {
      return true;
    }
    return widget.isHome && id == 'Emergency';
  }

  String get _categoryId {
    if (widget.categoryId != null) return widget.categoryId!;
    if (widget.isHome) return 'Home';
    return widget.title;
  }

  List<AacItem> get _boardItems {
    if (_categoryId == 'My words') {
      return AacButtonEditController.instance.applyAll(
        [
          ...AacCustomWordsController.instance.asItems,
          AacVocabulary.addWord,
          AacVocabulary.yes,
          AacVocabulary.no,
        ],
        'My words',
      );
    }
    final builtIn = widget.isHome
        ? AacVocabulary.homeWithMyWords(const [])
        : widget.items;
    return AacButtonEditController.instance.applyAll(
      AacVocabulary.insertCustom(
        builtIn,
        AacCustomWordsController.instance.itemsIn(_categoryId),
      ),
      _categoryId,
    );
  }

  List<AacItem> get _contentItems =>
      _boardItems.where((item) => !_isPinned(item)).toList();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AacAccessController.instance,
        AacCustomWordsController.instance,
        AacButtonEditController.instance,
        AppLanguage.instance,
      ]),
      builder: (context, _) {
        final settings = AacAccessController.instance.settings;
        return Scaffold(
          backgroundColor: const Color(0xFFF2F4F7),
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            toolbarHeight: settings.toolbarHeight,
            title: Text(
              widget.isHome || widget.title == 'Communicate'
                  ? AppLanguage.instance.t('communicate')
                  : AppLanguage.instance.aacLabel(widget.title),
              style: TextStyle(
                fontSize: settings.toolbarTitleSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            iconTheme: IconThemeData(
              size: settings.toolbarIconSize,
              color: Colors.white,
            ),
            actions: [
              IconButton(
                tooltip: 'Add a word',
                iconSize: settings.toolbarIconSize,
                icon: const Icon(Icons.add),
                onPressed: _openAddWord,
              ),
              IconButton(
                tooltip: AacButtonEditController.instance.editing
                    ? 'Done editing'
                    : 'Edit buttons',
                iconSize: settings.toolbarIconSize,
                isSelected: AacButtonEditController.instance.editing,
                icon: Icon(
                  AacButtonEditController.instance.editing
                      ? Icons.edit_off
                      : Icons.edit,
                ),
                onPressed: AacButtonEditController.instance.toggleEditing,
              ),
              IconButton(
                tooltip: 'Find a word',
                iconSize: settings.toolbarIconSize,
                icon: const Icon(Icons.search),
                onPressed: _openWordSearch,
              ),
              IconButton(
                tooltip: 'Communication accessibility',
                iconSize: settings.toolbarIconSize,
                icon: const Icon(Icons.accessibility_new),
                onPressed: () => showAacAccessSettings(context),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _buildMessageBar(settings),
                if (AacButtonEditController.instance.editing)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      settings.padding,
                      8,
                      settings.padding,
                      0,
                    ),
                    child: Material(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'Edit mode: tap a button to rename it, add a photo, or change the sound.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                Expanded(child: _buildBoard(settings)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareMessage(BuildContext context) async {
    final text = AacMessageController.instance.textController.text.trim();
    if (text.isEmpty) return;
    TypingPredictionStore.instance.learnFromCommitted(
      text,
      surface: 'communication',
    );

    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } on MissingPluginException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stop the app and run it again to turn sharing on.'),
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No share apps on this device. Message copied instead.',
          ),
        ),
      );
    }
  }

  Widget _messageActionButton({
    required double size,
    required AacAccessSettings settings,
    required String tooltip,
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filled(
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.blueGrey.shade200,
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(icon, size: settings.toolbarIconSize),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildMessageBar(AacAccessSettings settings) {
    final micSize = settings.toolbarHeight.clamp(48.0, 72.0);

    return ListenableBuilder(
      listenable: Listenable.merge([
        AacMessageController.instance,
        AppKeyboardController.instance,
      ]),
      builder: (context, _) {
        final message = AacMessageController.instance;
        final showPhraseRow = _phraseSuggestions.isNotEmpty &&
            !AacButtonEditController.instance.editing &&
            !AppKeyboardController.instance.showPredictBar;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            settings.padding,
            settings.padding,
            settings.padding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppKeyboardField(
                      controller: message.textController,
                      enableTidyUp: true,
                      enablePredictions: true,
                      predictionSurface: 'communication',
                      minLines: 1,
                      maxLines: 2,
                      style: TextStyle(fontSize: settings.tileFontSize + 2),
                      decoration: InputDecoration(
                        hintText: AppLanguage.instance.t('selectOrSpeak'),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: message.textController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.close),
                                onPressed: message.clear,
                              ),
                      ),
                    ),
                  ),
                  SizedBox(width: settings.gap),
                  _messageActionButton(
                    size: micSize,
                    settings: settings,
                    tooltip: message.isListening
                        ? 'Stop listening'
                        : 'Speech to text',
                    icon: message.isListening ? Icons.mic : Icons.mic_none,
                    backgroundColor:
                        message.isListening ? Colors.red : Colors.blueAccent,
                    onPressed: () async {
                      if (!message.isListening) {
                        await _flutterTts.stop();
                      }
                      await message.toggleListen();
                    },
                  ),
                  SizedBox(width: settings.gap),
                  Builder(
                    builder: (context) {
                      final canShare =
                          message.textController.text.trim().isNotEmpty;
                      return _messageActionButton(
                        size: micSize,
                        settings: settings,
                        tooltip: 'Share message',
                        icon: Icons.share,
                        backgroundColor: Colors.blueAccent,
                        onPressed: canShare
                            ? () => _shareMessage(context)
                            : null,
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                TypingPredictionStore.instance.hasSurvey
                    ? AppLanguage.instance.t('suggestionsUseSurvey')
                    : AppLanguage.instance.t('suggestionsGeneral'),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showPhraseRow) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _phraseSuggestions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final phrase = _phraseSuggestions[index];
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          onTap: () => _acceptPhrase(phrase),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.blueAccent),
                            ),
                            child: Text(
                              phrase,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.blueAccent,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (message.isListening) ...[
                const SizedBox(height: 6),
                const Text(
                  'Listening… speak now',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ] else if (message.errorMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  message.errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBoard(AacAccessSettings settings) {
    final content = _contentItems;
    final perPage = settings.buttonsPerPage;
    final pageCount = (content.length / perPage).ceil().clamp(1, 99);

    if (_pageIndex >= pageCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _pageIndex = pageCount - 1);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(pageCount - 1);
        }
      });
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Padding(
      padding: EdgeInsets.fromLTRB(
        settings.padding,
        settings.padding,
        settings.padding,
        8,
      ),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pageCount,
              onPageChanged: (index) {
                setState(() => _pageIndex = index);
                _schedulePredict();
              },
              itemBuilder: (context, page) {
                final slice =
                    content.skip(page * perPage).take(perPage).toList();
                return _buildPageGrid(settings, slice);
              },
            ),
          ),
          if (pageCount > 1) ...[
            SizedBox(height: settings.gap),
            _buildPageControls(settings, pageCount),
          ],
          SizedBox(height: settings.gap),
          _buildPinnedRow(settings),
        ],
      ),
      ),
    );
  }

  Widget _buildPageGrid(AacAccessSettings settings, List<AacItem> slice) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = settings.gridColumns(slice.length);
        final rows = settings.gridRows(slice.length);
        final gridWidth =
            constraints.maxWidth - (settings.gap * (columns - 1));
        final gridHeight =
            constraints.maxHeight - (settings.gap * (rows - 1));
        final cellWidth = gridWidth / columns;
        final cellHeight = gridHeight / rows;
        final aspectRatio =
            (cellWidth > 0 && cellHeight > 0) ? cellWidth / cellHeight : 1.0;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          clipBehavior: Clip.none,
          itemCount: slice.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: settings.gap,
            crossAxisSpacing: settings.gap,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            if (index >= slice.length) {
              return const SizedBox.shrink();
            }
            return _AacTile(
              key: _tileKey(slice[index]),
              item: slice[index],
              iconSize: settings.tileIconSize,
              fontSize: settings.tileFontSize,
              isArmed: _armedItem?.identity == slice[index].identity,
              isEditing: AacButtonEditController.instance.editing &&
                  !slice[index].isAddWord,
              isHighlighted: _highlightLabel?.toLowerCase() ==
                      slice[index].label.toLowerCase() ||
                  _highlightLabel?.toLowerCase() ==
                      slice[index].identity.toLowerCase(),
              isPredicted: _isPredicted(slice[index]),
              isDimmed: _isDimmed(slice[index]),
              holdProgress: _armedItem?.identity == slice[index].identity
                  ? _holdProgress
                  : 0,
            );
          },
        );
      },
    );
  }

  Widget _buildPageControls(AacAccessSettings settings, int pageCount) {
    final buttonSize = settings.pageControlSize;
    return Row(
      children: [
        SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: IconButton.filledTonal(
            onPressed: _pageIndex == 0
                ? null
                : () => _pageController.previousPage(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    ),
            iconSize: settings.toolbarIconSize * 0.75,
            icon: const Icon(Icons.chevron_left),
          ),
        ),
        Expanded(
          child: Text(
            'Page ${_pageIndex + 1} of $pageCount',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: settings.tileFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: IconButton.filledTonal(
            onPressed: _pageIndex >= pageCount - 1
                ? null
                : () => _pageController.nextPage(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    ),
            iconSize: settings.toolbarIconSize * 0.75,
            icon: const Icon(Icons.chevron_right),
          ),
        ),
      ],
    );
  }

  Widget _buildPinnedRow(AacAccessSettings settings) {
    final pinned = <AacItem>[
      if (widget.isHome) AacVocabulary.emergency,
      AacVocabulary.yes,
      AacVocabulary.no,
    ];

    return SizedBox(
      height: settings.coreRowHeight,
      child: Row(
        children: [
          for (var i = 0; i < pinned.length; i++) ...[
            if (i > 0) SizedBox(width: settings.gap),
            Expanded(
              child: _AacTile(
                key: _tileKey(pinned[i]),
                item: pinned[i],
                iconSize: settings.tileIconSize,
                fontSize: settings.tileFontSize,
                isArmed: _armedItem?.identity == pinned[i].identity,
                isEditing: AacButtonEditController.instance.editing,
                isHighlighted: _highlightLabel?.toLowerCase() ==
                        pinned[i].label.toLowerCase() ||
                    _highlightLabel?.toLowerCase() ==
                        pinned[i].identity.toLowerCase(),
                isPredicted: _isPredicted(pinned[i]),
                isDimmed: _isDimmed(pinned[i]),
                holdProgress: _armedItem?.identity == pinned[i].identity
                    ? _holdProgress
                    : 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> showAacAccessSettings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return ListenableBuilder(
          listenable: AacAccessController.instance,
          builder: (context, _) {
            final settings = AacAccessController.instance.settings;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Communication accessibility',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'These settings only change the communication boards.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Vocabulary Level',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Basic is a smaller starter board. Intermediate is the full board.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _AccessChoice(
                        label: 'Basic',
                        selected: settings.vocabLevel == AacVocabLevel.basic,
                        onTap: () => AacAccessController.instance
                            .update(vocabLevel: AacVocabLevel.basic),
                      ),
                      _AccessChoice(
                        label: 'Intermediate',
                        selected:
                            settings.vocabLevel == AacVocabLevel.intermediate,
                        onTap: () => AacAccessController.instance
                            .update(vocabLevel: AacVocabLevel.intermediate),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Buttons per page',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _AccessChoice(
                        label: 'Larger (6)',
                        selected: settings.gridSize == AacGridSize.large,
                        onTap: () => AacAccessController.instance
                            .update(gridSize: AacGridSize.large),
                      ),
                      _AccessChoice(
                        label: 'Standard (9)',
                        selected: settings.gridSize == AacGridSize.standard,
                        onTap: () => AacAccessController.instance
                            .update(gridSize: AacGridSize.standard),
                      ),
                      _AccessChoice(
                        label: 'More (16)',
                        selected: settings.gridSize == AacGridSize.compact,
                        onTap: () => AacAccessController.instance
                            .update(gridSize: AacGridSize.compact),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Button spacing',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _AccessChoice(
                        label: 'Tight',
                        selected: settings.spacing == AacSpacing.tight,
                        onTap: () => AacAccessController.instance
                            .update(spacing: AacSpacing.tight),
                      ),
                      _AccessChoice(
                        label: 'Normal',
                        selected: settings.spacing == AacSpacing.normal,
                        onTap: () => AacAccessController.instance
                            .update(spacing: AacSpacing.normal),
                      ),
                      _AccessChoice(
                        label: 'Wide',
                        selected: settings.spacing == AacSpacing.wide,
                        onTap: () => AacAccessController.instance
                            .update(spacing: AacSpacing.wide),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Toolbar size',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _AccessChoice(
                        label: 'Compact',
                        selected: settings.toolbarSize == AacToolbarSize.compact,
                        onTap: () => AacAccessController.instance
                            .update(toolbarSize: AacToolbarSize.compact),
                      ),
                      _AccessChoice(
                        label: 'Standard',
                        selected:
                            settings.toolbarSize == AacToolbarSize.standard,
                        onTap: () => AacAccessController.instance
                            .update(toolbarSize: AacToolbarSize.standard),
                      ),
                      _AccessChoice(
                        label: 'Large',
                        selected: settings.toolbarSize == AacToolbarSize.large,
                        onTap: () => AacAccessController.instance
                            .update(toolbarSize: AacToolbarSize.large),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Hold duration',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Keep your finger on a button for this long before it activates. Helps with shaking or accidental taps.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final seconds in AacAccessSettings.holdDurationOptions)
                        _AccessChoice(
                          label: seconds == 0 ? 'Off' : '${seconds}s',
                          selected: settings.holdDurationSeconds == seconds,
                          onTap: () => AacAccessController.instance
                              .update(holdDurationSeconds: seconds),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select on release',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The button is chosen when you lift your finger. Touch down, slide to the right button, then release.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _AccessChoice(
                        label: 'Off',
                        selected: !settings.selectOnRelease,
                        onTap: () => AacAccessController.instance
                            .update(selectOnRelease: false),
                      ),
                      _AccessChoice(
                        label: 'On',
                        selected: settings.selectOnRelease,
                        onTap: () => AacAccessController.instance
                            .update(selectOnRelease: true),
                      ),
                    ],
                  ),
                ],
              ),
              ),
              ),
            );
          },
        );
      },
    );
  }
}

enum _AacKeyboardPage { letters, numbers, symbols }

class AacKeyboardPage extends StatefulWidget {
  const AacKeyboardPage({
    super.key,
    required this.onOpenAccessSettings,
  });

  final VoidCallback onOpenAccessSettings;

  @override
  State<AacKeyboardPage> createState() => _AacKeyboardPageState();
}

class _AacKeyboardPageState extends State<AacKeyboardPage> {
  final FlutterTts _flutterTts = FlutterTts();
  bool _caps = false;
  _AacKeyboardPage _page = _AacKeyboardPage.letters;

  static const _letterRows = <List<String>>[
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
  ];

  static const _numberRows = <List<String>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['!', '@', '#', r'$', '%', '^', '&', '*'],
    ['(', ')', '.', ',', '?', '!'],
  ];

  static const _symbolRows = <List<String>>[
    ['-', '_', '=', '+', '[', ']', '{', '}'],
    ['\\', '|', '`', '~', ':', ';', '"', "'"],
    [',', '.', '<', '>', '/', '?'],
  ];

  @override
  void initState() {
    super.initState();
    _setupTts();
  }

  Future<void> _setupTts() async {
    await _flutterTts.setLanguage(AppLanguage.instance.ttsLanguage);
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setVolume(0.95);
    try {
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _speakText(String text) async {
    final phrase = text.trim();
    if (phrase.isEmpty) return;
    if (AacMessageController.instance.isListening) {
      await AacMessageController.instance.toggleListen();
    }
    await _flutterTts.stop();
    await _flutterTts.speak(phrase);
  }

  void _typeKey(String value, {bool speak = true}) {
    AacMessageController.instance.insertText(value);
    if (speak) {
      _speakText(value);
    }
  }

  Future<void> _speakMessage() async {
    await _speakText(AacMessageController.instance.textController.text);
  }

  Future<void> _tapPinned(AacItem item) async {
    await _speakText(item.spokenText);
    AacMessageController.instance.append(item.spokenText);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AacAccessController.instance,
        AacMessageController.instance,
      ]),
      builder: (context, _) {
        final settings = AacAccessController.instance.settings;
        return Scaffold(
          backgroundColor: const Color(0xFFF2F4F7),
          appBar: AppBar(
            toolbarHeight: settings.toolbarHeight,
            title: Text(
              'Keyboard',
              style: TextStyle(
                fontSize: settings.toolbarTitleSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            iconTheme: IconThemeData(
              size: settings.toolbarIconSize,
              color: Colors.white,
            ),
            actions: [
              IconButton(
                tooltip: 'Communication accessibility',
                iconSize: settings.toolbarIconSize,
                icon: const Icon(Icons.accessibility_new),
                onPressed: widget.onOpenAccessSettings,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _AacKeyboardMessageBar(
                  settings: settings,
                  flutterTts: _flutterTts,
                ),
                Expanded(child: _buildKeyboard(settings)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKeyboard(AacAccessSettings settings) {
    final rows = switch (_page) {
      _AacKeyboardPage.letters => _letterRows,
      _AacKeyboardPage.numbers => _numberRows,
      _AacKeyboardPage.symbols => _symbolRows,
    };
    final isLetters = _page == _AacKeyboardPage.letters;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        settings.padding,
        settings.padding,
        settings.padding,
        8,
      ),
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) SizedBox(height: settings.gap),
            _keyboardRow(
              settings: settings,
              expand: true,
              child: Row(
                children: [
                  if (r == rows.length - 1 && isLetters) ...[
                    _AacKey(
                      label: 'CAPS',
                      settings: settings,
                      background: _caps
                          ? const Color(0xFFBBDEFB)
                          : Colors.white,
                      onTap: () => setState(() => _caps = !_caps),
                    ),
                    SizedBox(width: settings.gap),
                  ],
                  for (var i = 0; i < rows[r].length; i++) ...[
                    if (i > 0) SizedBox(width: settings.gap),
                    _AacKey(
                      label: !isLetters || _caps
                          ? rows[r][i]
                          : rows[r][i].toLowerCase(),
                      settings: settings,
                      onTap: () {
                        final value = !isLetters || _caps
                            ? rows[r][i]
                            : rows[r][i].toLowerCase();
                        _typeKey(value);
                      },
                    ),
                  ],
                  if (r == rows.length - 1) ...[
                    SizedBox(width: settings.gap),
                    _AacKey(
                      label: '⌫',
                      settings: settings,
                      background: const Color(0xFFFFEBEE),
                      onTap: AacMessageController.instance.backspace,
                    ),
                  ],
                ],
              ),
            ),
          ],
          SizedBox(height: settings.gap),
          _keyboardRow(
            settings: settings,
            expand: true,
            child: Row(
              children: [
                _AacKey(
                  label: isLetters ? '123' : 'ABC',
                  settings: settings,
                  onTap: () => setState(() {
                    _page = isLetters
                        ? _AacKeyboardPage.numbers
                        : _AacKeyboardPage.letters;
                  }),
                ),
                if (_page == _AacKeyboardPage.numbers) ...[
                  SizedBox(width: settings.gap),
                  _AacKey(
                    label: '#+=',
                    settings: settings,
                    onTap: () => setState(() {
                      _page = _AacKeyboardPage.symbols;
                    }),
                  ),
                ],
                if (_page == _AacKeyboardPage.symbols) ...[
                  SizedBox(width: settings.gap),
                  _AacKey(
                    label: '123',
                    settings: settings,
                    onTap: () => setState(() {
                      _page = _AacKeyboardPage.numbers;
                    }),
                  ),
                ],
                SizedBox(width: settings.gap),
                _AacKey(
                  label: 'Space',
                  settings: settings,
                  flex: 3,
                  onTap: () => _typeKey(' ', speak: false),
                ),
                SizedBox(width: settings.gap),
                _AacKey(
                  label: '.',
                  settings: settings,
                  onTap: () => _typeKey('.'),
                ),
                SizedBox(width: settings.gap),
                _AacKey(
                  label: 'Speak',
                  settings: settings,
                  background: const Color(0xFFE8F5E9),
                  onTap: _speakMessage,
                ),
              ],
            ),
          ),
          SizedBox(height: settings.gap),
          SizedBox(
            height: settings.coreRowHeight,
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _tapPinned(AacVocabulary.emergency),
                    child: _AacTile(
                      item: AacVocabulary.emergency,
                      iconSize: settings.tileIconSize,
                      fontSize: settings.tileFontSize,
                    ),
                  ),
                ),
                SizedBox(width: settings.gap),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _tapPinned(AacVocabulary.yes),
                    child: _AacTile(
                      item: AacVocabulary.yes,
                      iconSize: settings.tileIconSize,
                      fontSize: settings.tileFontSize,
                    ),
                  ),
                ),
                SizedBox(width: settings.gap),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _tapPinned(AacVocabulary.no),
                    child: _AacTile(
                      item: AacVocabulary.no,
                      iconSize: settings.tileIconSize,
                      fontSize: settings.tileFontSize,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyboardRow({
    required AacAccessSettings settings,
    required bool expand,
    required Widget child,
  }) {
    if (expand) return Expanded(child: child);
    return SizedBox(height: settings.coreRowHeight, child: child);
  }
}

class _AacKeyboardMessageBar extends StatelessWidget {
  const _AacKeyboardMessageBar({
    required this.settings,
    required this.flutterTts,
  });

  final AacAccessSettings settings;
  final FlutterTts flutterTts;

  @override
  Widget build(BuildContext context) {
    final micSize = settings.toolbarHeight.clamp(48.0, 72.0);
    final message = AacMessageController.instance;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        settings.padding,
        settings.padding,
        settings.padding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: message.textController,
                  readOnly: true,
                  showCursor: true,
                  minLines: 1,
                  maxLines: 2,
                  style: TextStyle(fontSize: settings.tileFontSize + 2),
                  decoration: InputDecoration(
                    hintText: 'Type a message',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: message.textController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: message.clear,
                          ),
                  ),
                ),
              ),
              SizedBox(width: settings.gap),
              _keyboardActionButton(
                size: micSize,
                settings: settings,
                tooltip:
                    message.isListening ? 'Stop listening' : 'Speech to text',
                icon: message.isListening ? Icons.mic : Icons.mic_none,
                backgroundColor:
                    message.isListening ? Colors.red : Colors.blueAccent,
                onPressed: () async {
                  if (!message.isListening) {
                    await flutterTts.stop();
                  }
                  await message.toggleListen();
                },
              ),
              SizedBox(width: settings.gap),
              Builder(
                builder: (context) {
                  final canShare =
                      message.textController.text.trim().isNotEmpty;
                  return _keyboardActionButton(
                    size: micSize,
                    settings: settings,
                    tooltip: 'Share message',
                    icon: Icons.share,
                    backgroundColor: Colors.blueAccent,
                    onPressed: canShare
                        ? () => _shareKeyboardMessage(context)
                        : null,
                  );
                },
              ),
            ],
          ),
          if (message.isListening) ...[
            const SizedBox(height: 6),
            const Text(
              'Listening… speak now',
              style: TextStyle(color: Colors.red, fontSize: 13),
            ),
          ] else if (message.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              message.errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _keyboardActionButton({
  required double size,
  required AacAccessSettings settings,
  required String tooltip,
  required IconData icon,
  required Color backgroundColor,
  required VoidCallback? onPressed,
}) {
  return SizedBox(
    width: size,
    height: size,
    child: IconButton.filled(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.blueGrey.shade200,
        disabledForegroundColor: Colors.white70,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: Icon(icon, size: settings.toolbarIconSize),
      onPressed: onPressed,
    ),
  );
}

Future<void> _shareKeyboardMessage(BuildContext context) async {
  final text = AacMessageController.instance.textController.text.trim();
  if (text.isEmpty) return;
  final box = context.findRenderObject() as RenderBox?;
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } on MissingPluginException {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stop the app and run it again to turn sharing on.'),
      ),
    );
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No share apps on this device. Message copied instead.'),
      ),
    );
  }
}

class _AacKey extends StatelessWidget {
  const _AacKey({
    required this.label,
    required this.settings,
    required this.onTap,
    this.flex = 1,
    this.background = Colors.white,
  });

  final String label;
  final AacAccessSettings settings;
  final VoidCallback onTap;
  final int flex;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Material(
        color: background,
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: settings.tileFontSize + 4,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AacEditButtonSheet extends StatefulWidget {
  const _AacEditButtonSheet({
    required this.item,
    required this.categoryId,
  });

  final AacItem item;
  final String categoryId;

  @override
  State<_AacEditButtonSheet> createState() => _AacEditButtonSheetState();
}

class _AacEditButtonSheetState extends State<_AacEditButtonSheet> {
  late final TextEditingController _label;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _previewPlayer = AudioPlayer();
  String? _imagePath;
  String? _audioPath;
  bool _saving = false;
  bool _isRecording = false;
  String? _soundError;
  Timer? _recordLimit;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.item.label);
    _imagePath = widget.item.imagePath;
    _audioPath = widget.item.audioPath;
  }

  @override
  void dispose() {
    _recordLimit?.cancel();
    if (_isRecording) {
      _recorder.cancel();
    }
    _recorder.dispose();
    _previewPlayer.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 720,
      maxHeight: 720,
      imageQuality: 85,
    );
    if (picked == null) return;
    final key = AacButtonEditController.instance.keyFor(
      widget.item,
      widget.categoryId,
    );
    final saved = await AacButtonEditController.instance.savePickedPhoto(
      picked,
      key,
    );
    if (!mounted || saved == null) return;
    setState(() => _imagePath = saved);
  }

  String get _editKey => AacButtonEditController.instance.keyFor(
        widget.item,
        widget.categoryId,
      );

  Future<void> _pickSound() async {
    if (_isRecording) return;
    setState(() => _soundError = null);
    final result = await FilePicker.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    final saved = await AacButtonEditController.instance.saveAudioFile(
      path,
      _editKey,
    );
    if (!mounted) return;
    if (saved == null) {
      setState(() => _soundError = 'Could not add that sound file.');
      return;
    }
    setState(() => _audioPath = saved);
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      await _stopRecord();
      return;
    }

    setState(() => _soundError = null);
    if (AacMessageController.instance.isListening) {
      await AacMessageController.instance.toggleListen();
    }

    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() {
          _soundError = status.isPermanentlyDenied
              ? 'Enable the microphone in system settings to record a sound.'
              : 'Microphone permission is required to record a sound.';
        });
        if (status.isPermanentlyDenied) {
          await openAppSettings();
        }
        return;
      }
    }

    final dest = await AacButtonEditController.instance.createTempSoundPath();
    if (!mounted) return;

    try {
      await stopStoredButtonSound(_previewPlayer);
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          sampleRate: 16000,
          androidConfig: AndroidRecordConfig(
            useLegacy: false,
            manageBluetooth: false,
            muteAudio: false,
            audioSource: AndroidAudioSource.mic,
            speakerphone: false,
            audioManagerMode: AudioManagerMode.modeNormal,
          ),
          iosConfig: IosRecordConfig(
            categoryOptions: [
              IosAudioCategoryOption.defaultToSpeaker,
            ],
          ),
        ),
        path: dest,
      );
      if (!mounted) return;
      setState(() => _isRecording = true);
      _recordLimit = Timer(const Duration(seconds: 15), () {
        if (_isRecording) {
          _stopRecord();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _soundError = 'Could not start recording.');
    }
  }

  Future<void> _stopRecord() async {
    _recordLimit?.cancel();
    final path = await _recorder.stop();
    await resetButtonSoundAudio();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _isRecording = false);
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      setState(() => _soundError = 'Recording failed. Try again.');
      return;
    }
    if (File(path).lengthSync() < 1024) {
      setState(() {
        _soundError =
            'That recording was empty. Check the microphone and try again.';
      });
      return;
    }
    final silent = silentRecordingMessage(path);
    if (silent != null) {
      setState(() => _soundError = silent);
      return;
    }
    final saved = await AacButtonEditController.instance.saveAudioFile(
      path,
      _editKey,
    );
    try {
      await File(path).delete();
    } catch (_) {}
    if (!mounted) return;
    if (saved == null) {
      setState(() => _soundError = 'Could not save that recording.');
      return;
    }
    setState(() => _audioPath = saved);
  }

  Future<void> _previewSound() async {
    if (_audioPath == null) return;
    final playError = await playStoredButtonSound(_previewPlayer, _audioPath!);
    if (!mounted || playError == null) return;
    setState(() => _soundError = playError);
  }

  bool get _nameLocked =>
      AacButtonEditController.isCoreWord(widget.item, widget.categoryId);

  Future<void> _save() async {
    final name = _nameLocked
        ? widget.item.identity
        : _label.text.trim();
    if (name.isEmpty) return;
    if (_isRecording) {
      await _stopRecord();
    }
    setState(() => _saving = true);
    await AacButtonEditController.instance.update(
      widget.item,
      widget.categoryId,
      label: name,
      imagePath: _imagePath,
      audioPath: _audioPath,
      clearImage: _imagePath == null,
      clearAudio: _audioPath == null,
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final photoFile =
        _imagePath != null && File(_imagePath!).existsSync()
            ? File(_imagePath!)
            : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit button',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              _nameLocked
                  ? 'Core words keep their name. You can still change the picture or sound.'
                  : widget.item.isFolder
                      ? 'Change the name or replace the picture with a photo from your phone.'
                      : 'Change the name, picture, or the sound this button plays.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
            ),
            const SizedBox(height: 16),
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: widget.item.tileColor ?? const Color(0xFFE3F2FD),
                backgroundImage:
                    photoFile != null ? FileImage(photoFile) : null,
                child: photoFile == null
                    ? Icon(
                        widget.item.icon,
                        size: 40,
                        color: widget.item.color,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _label,
              enabled: !_nameLocked,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _nameLocked ? 'Core word (locked)' : 'Button name',
                filled: true,
                fillColor: const Color(0xFFF2F4F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                ),
              ],
            ),
            if (_imagePath != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _imagePath = null),
                child: const Text('Use original icon'),
              ),
            ],
            if (!widget.item.isFolder) ...[
              const SizedBox(height: 16),
              const Text(
                'Sound',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                _isRecording
                    ? 'Recording… tap Stop when you are done (15 seconds max).'
                    : 'Add a downloaded sound or record your voice. This plays instead of the automated voice.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isRecording ? null : _pickSound,
                      icon: const Icon(Icons.audio_file),
                      label: const Text('File'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _toggleRecord,
                      icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                      label: Text(_isRecording ? 'Stop' : 'Record'),
                      style: _isRecording
                          ? OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              if (_audioPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Custom sound ready',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _isRecording ? null : _previewSound,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                    ),
                    TextButton(
                      onPressed: _isRecording
                          ? null
                          : () => setState(() => _audioPath = null),
                      child: const Text('Use automated voice'),
                    ),
                  ],
                ),
              ],
              if (_soundError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _soundError!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save changes'),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _AacAddWordSheet extends StatefulWidget {
  const _AacAddWordSheet({required this.initialCategoryId});

  final String initialCategoryId;

  @override
  State<_AacAddWordSheet> createState() => _AacAddWordSheetState();
}

class _AacAddWordSheetState extends State<_AacAddWordSheet> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _speak = TextEditingController();
  IconData _icon = AacCustomWordsController.iconChoices.first;
  late String _categoryId;

  AacWordCategory get _category => AacWordCategory.byId(_categoryId);

  @override
  void initState() {
    super.initState();
    final selected = AacWordCategory.byId(widget.initialCategoryId);
    _categoryId = AacWordCategory.visible.any((category) => category.id == selected.id)
        ? selected.id
        : AacWordCategory.home.id;
  }

  @override
  void dispose() {
    _label.dispose();
    _speak.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) return;
    await AacCustomWordsController.instance.add(
      label: label,
      speak: _speak.text,
      icon: _icon,
      categoryId: _categoryId,
    );
    _label.clear();
    _speak.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "$label" in ${_category.label}')),
    );
    setState(() {});
  }

  Future<void> _delete(AacCustomWord word) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove this word?'),
          content: Text('Remove "${word.label}" from My words?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await AacCustomWordsController.instance.remove(word.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final words = AacCustomWordsController.instance.words;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add a word',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Choose a category. The word uses that folder’s color and appears there.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black54,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Word or phrase',
                  hintText: 'Grandma',
                  filled: true,
                  fillColor: const Color(0xFFF2F4F7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _speak,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'Speak this (optional)',
                  hintText: 'I want grandma',
                  filled: true,
                  fillColor: const Color(0xFFF2F4F7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Icon',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: AacCustomWordsController.iconChoices.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final icon = AacCustomWordsController.iconChoices[index];
                    final selected = icon.codePoint == _icon.codePoint;
                    return IconButton.filledTonal(
                      onPressed: () => setState(() => _icon = icon),
                      style: IconButton.styleFrom(
                        backgroundColor: selected
                            ? _category.color.withValues(alpha: 0.25)
                            : const Color(0xFFF2F4F7),
                        foregroundColor:
                            selected ? _category.color : Colors.black54,
                      ),
                      icon: Icon(icon),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Category',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 170,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final group in AacWordCategory.visibleGroups) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 6),
                          child: Text(
                            group,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final category
                                in AacWordCategory.inGroup(group))
                              ChoiceChip(
                                avatar: CircleAvatar(
                                  backgroundColor: category.color,
                                ),
                                label: Text(category.label),
                                selected: _categoryId == category.id,
                                selectedColor: category.background,
                                onSelected: (_) {
                                  setState(() => _categoryId = category.id);
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.add),
                label: const Text('Save word'),
              ),
              const SizedBox(height: 16),
              Text(
                'Your words',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: words.isEmpty
                    ? const Center(
                        child: Text(
                          'No custom words yet.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      )
                    : ListView.separated(
                        itemCount: words.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final word = words[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: word.color.withValues(alpha: 0.18),
                              child: Icon(word.icon, color: word.color),
                            ),
                            title: Text(
                              word.label,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              word.speak == word.label
                                  ? word.category.id
                                  : '${word.category.id} · ${word.speak}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(word),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AacSearchSheet extends StatefulWidget {
  const _AacSearchSheet();

  @override
  State<_AacSearchSheet> createState() => _AacSearchSheetState();
}

class _AacSearchSheetState extends State<_AacSearchSheet> {
  final TextEditingController _query = TextEditingController();
  List<AacSearchHit> _results = const [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _results = AacVocabulary.search(value));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Find a word',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Type a word, like Home, to open that button.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black54,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search words',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFFF2F4F7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _query.clear();
                            _onQueryChanged('');
                          },
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          _query.text.trim().isEmpty
                              ? 'Start typing to search the board.'
                              : 'No words match that search.',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final hit = _results[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              backgroundColor:
                                  hit.item.tileColor ?? const Color(0xFFE3F2FD),
                              child: Icon(hit.item.icon, color: hit.item.color),
                            ),
                            title: Text(
                              hit.item.displayLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(hit.location),
                            trailing: Icon(
                              hit.item.isFolder
                                  ? Icons.folder_open
                                  : Icons.arrow_forward,
                              color: Colors.blueAccent,
                            ),
                            onTap: () => Navigator.pop(context, hit),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessChoice extends StatelessWidget {
  const _AccessChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _AacTile extends StatelessWidget {
  const _AacTile({
    super.key,
    required this.item,
    this.iconSize = 36,
    this.fontSize = 14,
    this.isArmed = false,
    this.isHighlighted = false,
    this.isPredicted = false,
    this.isDimmed = false,
    this.isEditing = false,
    this.holdProgress = 0,
  });

  final AacItem item;
  final double iconSize;
  final double fontSize;
  final bool isArmed;
  final bool isHighlighted;
  final bool isPredicted;
  final bool isDimmed;
  final bool isEditing;
  final double holdProgress;

  @override
  Widget build(BuildContext context) {
    final foreground = item.foregroundColor ?? Colors.black87;
    final background = item.tileColor ??
        (item.isFolder ? const Color(0xFFE3F2FD) : Colors.white);
    final standOut = isPredicted || isHighlighted;
    final highlight = Color.alphaBlend(
      (isPredicted ? Colors.amber : Colors.blueAccent)
          .withValues(alpha: isPredicted ? 0.28 : 0.18),
      background,
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: isDimmed ? 0.32 : 1,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        scale: isPredicted ? 1.08 : 1,
        child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPredicted
              ? const Color(0xFFFFB300)
              : isHighlighted
                  ? Colors.amber
                  : Colors.transparent,
          width: isPredicted
              ? 4
              : isHighlighted
                  ? 3
                  : 0,
        ),
        boxShadow: standOut
            ? [
                BoxShadow(
                  color: (isPredicted ? const Color(0xFFFFB300) : Colors.amber)
                      .withValues(alpha: isPredicted ? 0.7 : 0.45),
                  blurRadius: isPredicted ? 16 : 10,
                  spreadRadius: isPredicted ? 2 : 1,
                ),
              ]
            : null,
      ),
      child: ColorFiltered(
        colorFilter: isDimmed
            ? const ColorFilter.matrix(<double>[
                0.35, 0.45, 0.1, 0, 20,
                0.35, 0.45, 0.1, 0, 20,
                0.35, 0.45, 0.1, 0, 20,
                0, 0, 0, 1, 0,
              ])
            : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
        child: Material(
        color: isArmed || standOut ? highlight : background,
        borderRadius: BorderRadius.circular(16),
        elevation: isArmed || standOut ? 8 : 4,
        child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (item.hasPhoto && File(item.imagePath!).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(item.imagePath!),
                        width: iconSize + 8,
                        height: iconSize + 8,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Icon(item.icon, size: iconSize, color: item.color),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.displayLabel,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isPredicted)
              Positioned(
                right: 0,
                top: 0,
                child: Icon(
                  Icons.auto_awesome,
                  size: fontSize + 2,
                  color: const Color(0xFFFF8F00),
                ),
              ),
            if (isEditing)
              Positioned(
                left: 0,
                top: 0,
                child: Icon(
                  Icons.edit,
                  size: fontSize,
                  color: Colors.orange,
                ),
              ),
            if (item.isFolder && !isPredicted)
              Positioned(
                right: 0,
                top: 0,
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: fontSize,
                  color: Colors.blueAccent,
                ),
              ),
            if (isArmed && holdProgress > 0)
              Positioned(
                left: 4,
                right: 4,
                bottom: 2,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: holdProgress,
                    minHeight: 5,
                    backgroundColor: Colors.black12,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
      ),
        ),
      ),
    );
  }
}
