import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Remembers what this person types and taps so next-word guesses improve.
class TypingPredictionStore {
  TypingPredictionStore._();
  static final TypingPredictionStore instance = TypingPredictionStore._();

  static const _maxPrefixes = 80;
  static const _maxNext = 8;
  static const _maxStarters = 40;
  static const _maxAccepted = 40;
  static const _maxRecent = 40;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _uid;
  var _started = false;
  Timer? _saveTimer;
  String? conversationHint;
  String _lastSurface = '';
  String _lastTyped = '';
  Map<String, dynamic> _survey = {};

  bool get hasSurvey => _survey.isNotEmpty;

  String get surveyPrompt {
    if (_survey.isEmpty) {
      return 'No questionnaire yet. Use general, simple hospital language.';
    }
    return surveySummary;
  }

  String get surveySummary {
    if (_survey.isEmpty) return '';
    final lines = <String>[];
    void addLine(String label, dynamic value) {
      final text = _valueText(value);
      if (text.isEmpty) return;
      lines.add('$label: $text');
    }

    addLine('Pets', _survey['pets']);
    addLine('About their pets', _survey['petsNote']);
    addLine('For fun', _survey['fun']);
    addLine('Other things they enjoy', _survey['funNote']);
    addLine('People', _survey['people']);
    addLine('What helps', _survey['comfort']);
    addLine('Food and drink', _survey['food']);
    addLine('Home and care', _survey['home']);
    addLine('Names and nicknames', _survey['names']);
    addLine('Things they want to say', _survey['talk']);
    addLine('Usual day', _survey['routine']);
    addLine('Anything else', _survey['more']);
    addLine('Other notes', _survey['notes']);
    return lines.join('\n');
  }

  List<String> surveyPhrases() {
    final phrases = <String>[];
    void add(String value) {
      final phrase = value.trim();
      if (phrase.isEmpty) return;
      if (phrases.any((item) => item.toLowerCase() == phrase.toLowerCase())) {
        return;
      }
      phrases.add(phrase);
    }

    void addFromAnswer(String answer) {
      final text = answer.trim();
      if (text.isEmpty) return;
      add(_clip(text, 48));
      for (final part in text.split(RegExp(r'[,;/]|\band\b|\.'))) {
        final bit = part.trim();
        final words = bit.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
        if (words.length >= 1 && words.length <= 6) add(bit);
      }
      final lower = text.toLowerCase();
      if (lower.contains('dog')) add('my dog');
      if (lower.contains('cat')) add('my cat');
      if (lower.contains('pet')) add('my pet');
      if (lower.contains('music')) add('music');
      if (lower.contains('family')) add('my family');
      if (lower.contains('friend')) add('my friends');
      if (lower.contains('coffee')) add('coffee');
      if (lower.contains('tea')) add('tea');
      if (lower.contains('water')) add('water');
    }

    for (final value in _survey.values) {
      addFromAnswer(_valueText(value));
    }
    return phrases;
  }

  Future<void> applySurvey(Map<String, dynamic> survey) async {
    await start();
    _survey = Map<String, dynamic>.from(survey);
    for (final phrase in surveyPhrases()) {
      _bump(_starters, _clip(phrase, 48), _maxStarters);
      _bump(_accepted, _clip(phrase, 48), _maxAccepted);
    }
    await _save();
  }

  final Map<String, Map<String, int>> _next = {};
  final Map<String, int> _starters = {};
  final Map<String, int> _accepted = {};
  final List<String> _recent = [];

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('ai_memory').doc('typing');
  }

  Future<void> start() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    if (_started && _uid == uid) return;
    _uid = uid;
    _started = true;
    await _load();
    await _loadSurvey();
  }

  Future<void> reset() async {
    _saveTimer?.cancel();
    await _save();
    _uid = null;
    _started = false;
    conversationHint = null;
    _lastSurface = '';
    _lastTyped = '';
    _survey = {};
    _next.clear();
    _starters.clear();
    _accepted.clear();
    _recent.clear();
  }

  void setConversationHint(String? text) {
    final trimmed = text?.trim() ?? '';
    conversationHint = trimmed.isEmpty ? null : _clip(trimmed, 220);
  }

  void learnFromCommitted(String text, {String surface = ''}) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    unawaited(start());
    _lastSurface = surface;
    final words = _words(cleaned);
    if (words.isEmpty) return;

    if (words.length <= 6) {
      _bump(_starters, _clip(cleaned, 48), _maxStarters);
    } else {
      _bump(_starters, words.take(3).join(' '), _maxStarters);
    }

    for (var i = 0; i < words.length - 1; i++) {
      _bumpNext(words[i], words[i + 1]);
      if (i > 0) {
        _bumpNext('${words[i - 1]} ${words[i]}', words[i + 1]);
      }
    }

    _recent.removeWhere((item) => item.toLowerCase() == cleaned.toLowerCase());
    _recent.insert(0, _clip(cleaned, 200));
    if (_recent.length > _maxRecent) {
      _recent.removeRange(_maxRecent, _recent.length);
    }
    _scheduleSave();
  }

  /// Learns as soon as a word or sentence is finished, not only on Send.
  void learnFromTyping(String text, {String surface = ''}) {
    if (text == _lastTyped) return;
    final endedWord = text.endsWith(' ') || RegExp(r'[.!?]\s*$').hasMatch(text);
    if (!endedWord) return;
    _lastTyped = text;
    unawaited(start());
    _lastSurface = surface;
    final words = _words(text);
    if (words.isEmpty) return;
    if (words.length == 1) {
      _bump(_starters, words.first, _maxStarters);
      _scheduleSave();
      return;
    }
    _bumpNext(words[words.length - 2], words.last);
    if (words.length >= 3) {
      _bumpNext(
        '${words[words.length - 3]} ${words[words.length - 2]}',
        words.last,
      );
    }
    _scheduleSave();
  }

  void learnAccepted(String prefix, String suggestion) {
    final phrase = suggestion.trim();
    if (phrase.isEmpty) return;
    unawaited(start());
    _bump(_accepted, _clip(phrase, 48), _maxAccepted);
    final key = prefix.trim().toLowerCase();
    if (key.isNotEmpty) {
      _bumpNext(key, phrase.toLowerCase());
    }
    _scheduleSave();
  }

  List<String> localSuggestions(String current, {String surface = ''}) {
    final text = current.trimRight();
    final picks = <String>[];

    void add(String value) {
      final phrase = value.trim();
      if (phrase.isEmpty) return;
      if (picks.any((item) => item.toLowerCase() == phrase.toLowerCase())) {
        return;
      }
      picks.add(phrase);
    }

    if (text.isEmpty) {
      for (final phrase in surveyPhrases()) {
        add(phrase);
      }
      for (final phrase in _ranked(_starters)) {
        add(phrase);
      }
      for (final phrase in _ranked(_accepted)) {
        add(phrase);
      }
      for (final seed in _seedsFor(surface)) {
        add(seed);
      }
      return picks.take(6).toList();
    }

    final trailingSpace = current.endsWith(' ');
    final words = _words(text);
    if (words.isEmpty) return _seedsFor(surface);

    if (trailingSpace) {
      final one = words.last;
      final two = words.length >= 2 ? '${words[words.length - 2]} $one' : '';
      for (final next in _ranked(_next[two] ?? const {})) {
        add(next);
      }
      for (final next in _ranked(_next[one] ?? const {})) {
        add(next);
      }
    } else {
      final partial = words.last;
      final previous = words.length >= 2 ? words[words.length - 2] : '';
      for (final next in _ranked(_next[previous] ?? const {})) {
        if (next.startsWith(partial)) add(next);
      }
      for (final phrase in [..._ranked(_accepted), ..._ranked(_starters)]) {
        if (phrase.toLowerCase().startsWith(partial)) add(phrase);
      }
      for (final seed in _seedsFor(surface)) {
        if (seed.toLowerCase().startsWith(partial)) add(seed);
      }
    }

    if (picks.isEmpty) {
      for (final seed in _seedsFor(surface)) {
        add(seed);
      }
    }
    return picks.take(6).toList();
  }

  List<String> learnedHints({int limit = 18}) {
    final hints = <String>[
      ...surveyPhrases(),
      ..._recent.take(8),
      ..._ranked(_accepted).take(6),
      ..._ranked(_starters).take(6),
    ];
    final unique = <String>[];
    for (final hint in hints) {
      if (unique.any((item) => item.toLowerCase() == hint.toLowerCase())) {
        continue;
      }
      unique.add(hint);
      if (unique.length >= limit) break;
    }
    return unique;
  }

  List<String> _seedsFor(String surface) {
    if (surface == 'community') {
      return const [
        'Has anyone',
        'I have a question',
        'Thank you',
        'I feel',
        'Looking for advice',
        'This helped',
      ];
    }
    if (surface == 'communication') {
      return const [
        'I',
        'I want',
        'I need',
        'help',
        'I feel',
        'Thank you',
        'Bathroom',
      ];
    }
    return const [
      'Hello',
      'I feel',
      'I need',
      'Can you help',
      'Thank you',
      'What should I',
    ];
  }

  Future<void> _load() async {
    final doc = _doc;
    if (doc == null) return;
    try {
      final snap = await doc.get();
      final data = snap.data();
      if (data == null) return;
      _next
        ..clear()
        ..addAll(_mapOfCounts(data['next']));
      _starters
        ..clear()
        ..addAll(_counts(data['starters']));
      _accepted
        ..clear()
        ..addAll(_counts(data['accepted']));
      _recent
        ..clear()
        ..addAll(
          ((data['recent'] as List?) ?? const [])
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty),
        );
    } catch (error) {
      if (kDebugMode) debugPrint('Typing memory load failed: $error');
    }
  }

  Future<void> _loadSurvey() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final raw = snap.data()?['survey'];
      if (raw is Map) {
        _survey = Map<String, dynamic>.from(raw);
      } else {
        _survey = {};
      }
    } catch (error) {
      if (kDebugMode) debugPrint('Survey load failed: $error');
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    final doc = _doc;
    if (doc == null) return;
    try {
      await doc.set({
        'next': _next,
        'starters': _starters,
        'accepted': _accepted,
        'recent': _recent,
        'lastSurface': _lastSurface,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      if (kDebugMode) debugPrint('Typing memory save failed: $error');
    }
  }

  void _bumpNext(String prefix, String next) {
    if (prefix.isEmpty || next.isEmpty) return;
    var inner = _next[prefix];
    if (inner == null) {
      if (_next.length >= _maxPrefixes) {
        _next.remove(_next.keys.first);
      }
      inner = <String, int>{};
      _next[prefix] = inner;
    }
    _bump(inner, next, _maxNext);
  }

  void _bump(Map<String, int> counts, String key, int maxKeys) {
    counts[key] = (counts[key] ?? 0) + 1;
    if (counts.length <= maxKeys) return;
    final weakest = counts.entries
        .reduce((a, b) => a.value <= b.value ? a : b)
        .key;
    counts.remove(weakest);
  }

  List<String> _ranked(Map<String, int> counts) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((entry) => entry.key).toList();
  }

  Map<String, int> _counts(dynamic raw) {
    if (raw is! Map) return {};
    final out = <String, int>{};
    for (final entry in raw.entries) {
      final key = '${entry.key}'.trim();
      final value = entry.value;
      if (key.isEmpty) continue;
      out[key] = value is int ? value : int.tryParse('$value') ?? 1;
    }
    return out;
  }

  Map<String, Map<String, int>> _mapOfCounts(dynamic raw) {
    if (raw is! Map) return {};
    final out = <String, Map<String, int>>{};
    for (final entry in raw.entries) {
      final key = '${entry.key}'.trim();
      if (key.isEmpty) continue;
      out[key] = _counts(entry.value);
    }
    return out;
  }

  List<String> _words(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9'\s]"), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
  }

  String _valueText(dynamic value) {
    if (value is List) {
      return value
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .join(', ');
    }
    return '$value'.trim();
  }

  String _clip(String text, int max) {
    if (text.length <= max) return text;
    return text.substring(0, max).trim();
  }
}
