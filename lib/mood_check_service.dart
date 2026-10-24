import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:swiftspeak/app_language.dart';

class MoodCheckService {
  MoodCheckService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  final String _baseUrl = 'https://api.openai.com/v1';

  String _requireApiKey() {
    final key = dotenv.env['OPENAI_API_KEY'];
    if (key == null || key.trim().isEmpty) {
      throw Exception(
        'OPENAI_API_KEY not found. Check your .env and that dotenv.load() runs before the app.',
      );
    }
    return key.trim();
  }

  Future<String> generateInsight({
    required String moodToday,
    required double stress,
    required double energy,
    required double hopefulness,
    required double confidence,
  }) async {
    final apiKey = _requireApiKey();

    final prompt =
        "You are a supportive recovery assistant.\n\n"
        "User Mood Data:\n"
        "- Mood today: $moodToday\n"
        "- Stress: ${stress.toStringAsFixed(1)}/5\n"
        "- Energy: ${energy.toStringAsFixed(1)}/5\n"
        "- Hopefulness: ${hopefulness.toStringAsFixed(1)}/5\n"
        "- Confidence: ${confidence.toStringAsFixed(1)}/5\n\n"
        "Write 3–5 encouraging sentences.\n"
        "Be supportive, calm, and practical.\n"
        "Do NOT provide medical diagnosis.\n"
        "${AppLanguage.instance.replyLanguageRule}\n";

    // Responses API request body
    final body = <String, dynamic>{
      'model': 'gpt-4o-mini',
      'input': prompt,
    };

    final uri = Uri.parse('$_baseUrl/responses');

    final resp = await http.post(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint('OpenAI HTTP ${resp.statusCode}: ${resp.body}');
      }
      throw Exception('OpenAI error ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);

    if (kDebugMode) {
      final preview =
      resp.body.length > 600 ? resp.body.substring(0, 600) : resp.body;
      debugPrint('OpenAI raw preview: $preview');
    }

    final insight = _extractText(decoded);
    if (insight.trim().isEmpty) {
      throw Exception('OpenAI response missing text content.');
    }
    return insight.trim();
  }

  /// Saves to:
  /// users/{uid}/mood_checks/{autoId}
  /// and returns the new document id.
  Future<String> saveMoodEntry({
    required String moodToday,
    required double stress,
    required double energy,
    required double hopefulness,
    required double confidence,
    required String insight,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in. Please log in first.');
    }

    final ref = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('mood_checks')
        .add(<String, dynamic>{
      'moodToday': moodToday,
      'stress': stress,
      'energy': energy,
      'hopefulness': hopefulness,
      'confidence': confidence,
      'insight': insight,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  /// Tries multiple known OpenAI response shapes.
  String _extractText(dynamic decoded) {
    try {
      // 1) Responses API convenience field
      final outputText = decoded is Map ? decoded['output_text'] : null;
      if (outputText is String && outputText.isNotEmpty) return outputText;

      // 2) Responses API structured output
      final output = decoded is Map ? decoded['output'] : null;
      if (output is List && output.isNotEmpty) {
        final first = output.first;
        if (first is Map) {
          final content = first['content'];
          if (content is List && content.isNotEmpty) {
            final c0 = content.first;
            if (c0 is Map && c0['text'] is String) {
              return c0['text'] as String;
            }
          }
        }
      }

      // 3) Chat Completions fallback
      final choices = decoded is Map ? decoded['choices'] : null;
      if (choices is List && choices.isNotEmpty) {
        final c0 = choices.first;
        if (c0 is Map) {
          final msg = c0['message'];
          if (msg is Map && msg['content'] is String) {
            return msg['content'] as String;
          }
        }
      }
    } catch (_) {}
    return '';
  }
}