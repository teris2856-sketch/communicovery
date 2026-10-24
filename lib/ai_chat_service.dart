import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:swiftspeak/app_language.dart';

class AiChatService {
  static const String _persona =
      "You are an AI chatbot that helps stroke patients communicate and supports them on their healing journey in a hospital. "
      "Answer the questions as if a stroke patient was asking them.";

  final String _baseUrl = "https://api.openai.com/v1/chat/completions";

  String _apiKey() {
    final key = dotenv.env['OPENAI_API_KEY'];
    if (key == null || key.trim().isEmpty) {
      throw Exception("Missing OPENAI_API_KEY. Check your .env file.");
    }
    return key.trim();
  }

  Map<String, String> _headers() => {
    "Authorization": "Bearer ${_apiKey()}",
    "Content-Type": "application/json",
  };

  Future<String> generateAssistantReply({
    required List<Map<String, dynamic>> chatMessages,
  }) async {
    final convo = _formatConversation(chatMessages);

    final userPrompt = """
Rules:
- Be calm, kind, and practical.
- Keep answers clear and easy to understand.
- Do NOT provide a medical diagnosis.
- Encourage safety: if symptoms are severe or urgent, advise asking a nurse/doctor immediately.
- Ask 1 short follow-up question if it helps.

Conversation so far:
$convo

${AppLanguage.instance.replyLanguageRule}

Now respond to the patient's last message.
""";

    final json = await _postToOpenAI(system: _persona, user: userPrompt);
    final text = _extractChatCompletionText(json);

    if (text.isEmpty) {
      if (kDebugMode) debugPrint("OpenAI raw JSON (empty): ${jsonEncode(json)}");
      throw Exception("Empty AI response.");
    }

    return text;
  }

  Future<String> generateRecommendation({
    required List<Map<String, dynamic>> chatMessages,
  }) async {
    final convo = _formatConversation(chatMessages);

    final userPrompt = """
Task:
Analyze the conversation and give a short supportive recommendation for the patient.

Rules:
- 3 to 6 sentences max.
- Practical, calming, hospital-appropriate.
- Do NOT provide a medical diagnosis.
- If urgent red flags are present, tell them to seek immediate help from nurse/doctor.
- Keep language simple.
${AppLanguage.instance.replyLanguageRule}

Conversation:
$convo
""";

    final json = await _postToOpenAI(system: _persona, user: userPrompt);
    final text = _extractChatCompletionText(json);

    if (text.isEmpty) {
      if (kDebugMode) debugPrint("OpenAI raw JSON (empty rec): ${jsonEncode(json)}");
      throw Exception("Empty AI response.");
    }

    return text;
  }

  Future<String> generateChatTitle({
    required List<Map<String, dynamic>> chatMessages,
  }) async {
    final convo = _formatConversation(chatMessages);

    final sys = "You create short chat titles.";
    final userPrompt = """
Create a short title (2 to 6 words) based on the conversation.
No quotes. No punctuation at the end.
Avoid personal data. Keep it general.
${AppLanguage.instance.replyLanguageRule}

Conversation:
$convo
""";

    final json = await _postToOpenAI(system: sys, user: userPrompt);
    final text = _extractChatCompletionText(json);

    final cleaned = text.replaceAll(RegExp(r'["\n]'), '').trim();
    if (cleaned.isEmpty) return "";
    return cleaned.split(RegExp(r'\s+')).take(6).join(' ');
  }

  Future<Map<String, String>> translateTexts({
    required Map<String, String> texts,
    required String targetLanguage,
  }) async {
    if (texts.isEmpty) return const {};

    final payload = <String, String>{
      for (final entry in texts.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value,
    };
    if (payload.isEmpty) return Map<String, String>.from(texts);

    final json = await _postToOpenAI(
      system:
          'You translate community post text. '
          'Return a JSON object with the exact same keys. '
          'Translate each value into $targetLanguage. '
          'Keep @mentions, names, numbers, and emoji unchanged. '
          'If a value is already in $targetLanguage, copy it unchanged. '
          'Do not add extra keys or explanation.',
      user: jsonEncode(payload),
      temperature: 0,
      maxTokens: 800,
    );
    final raw = _extractChatCompletionText(json);
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    final translated = <String, String>{};
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(raw.substring(start, end + 1));
        if (decoded is Map) {
          decoded.forEach((key, value) {
            translated['$key'] = '$value';
          });
        }
      } catch (_) {}
    }

    return {
      for (final entry in texts.entries)
        entry.key: (translated[entry.key] ?? entry.value).toString(),
    };
  }

  Future<String> tidyText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return raw;

    final json = await _postToOpenAI(
      system:
          'You fix typos, spacing, punctuation, and capitalization only. '
          'Capitalize the first letter of the text and the first letter of each sentence. '
          'Capitalize the pronoun I. Keep the same meaning, names, and language. '
          'Return only the corrected text, with no quotes or explanation.',
      user: text,
      temperature: 0,
    );
    final cleaned = _extractChatCompletionText(json);
    return _fixCapitalization(cleaned.isEmpty ? raw : cleaned);
  }

  Future<String> rewriteText({
    required String text,
    required String instruction,
  }) async {
    final source = text.trim();
    final request = instruction.trim();
    if (source.isEmpty || request.isEmpty) return text;

    final json = await _postToOpenAI(
      system:
          'You rewrite the user\'s message using their instruction. '
          'Keep it in first person if it already is. '
          'Do not add quotes, labels, or extra explanation. '
          'Return only the rewritten message.',
      user: 'Instruction: $request\n\nMessage:\n$source',
      temperature: 0.5,
    );
    final rewritten = _extractChatCompletionText(json);
    return rewritten.isEmpty ? text : rewritten;
  }

  String _fixCapitalization(String text) {
    if (text.isEmpty) return text;
    final buffer = StringBuffer();
    var capitalizeNext = true;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (capitalizeNext && RegExp(r'[A-Za-z]').hasMatch(ch)) {
        buffer.write(ch.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(ch);
        if (ch == '.' || ch == '!' || ch == '?') {
          capitalizeNext = true;
        }
      }
    }
    return buffer.toString().replaceAllMapped(
      RegExp(r'\bi\b'),
      (_) => 'I',
    );
  }

  Future<List<String>> predictNextAacButtons({
    required String currentMessage,
    required List<String> buttonLabels,
    String? personProfile,
  }) async {
    final labels = <String>[];
    final seen = <String>{};
    for (final raw in buttonLabels) {
      final label = raw.trim();
      if (label.isEmpty) continue;
      final key = label.toLowerCase();
      if (!seen.add(key)) continue;
      labels.add(label);
    }
    if (labels.isEmpty) return const [];

    final message = currentMessage.trim();
    final listed = labels.map((label) => '- $label').join('\n');
    final profile = (personProfile ?? '').trim().isEmpty
        ? 'No questionnaire yet. Use general, simple hospital language.'
        : personProfile!.trim();
    final json = await _postToOpenAI(
      system:
          'You predict the next AAC communication button a hospital patient is likely to press. '
          'Choose only from the provided button labels. Copy labels exactly. '
          'If the questionnaire is relevant, prefer matching buttons (pets, hobbies, people, comfort). '
          'Return a JSON array of 1 or 2 labels, most likely first. No other text.',
      user: '''
Current message: ${message.isEmpty ? '(empty — they have not started yet)' : message}

About this person:
$profile

Visible buttons:
$listed

Predict the next button they might press.
''',
      temperature: 0.1,
      maxTokens: 60,
    );
    return _extractLabelList(_extractChatCompletionText(json), labels);
  }

  Future<List<String>> predictTypingSuggestions({
    required String currentText,
    required String surface,
    List<String> learnedHints = const [],
    String? conversationHint,
    String? personProfile,
  }) async {
    final where = switch (surface) {
      'community' => 'a recovery community post or reply',
      'communication' => 'an AAC communication message on a hospital board',
      _ => 'a chat with a hospital support chatbot',
    };
    final learned = learnedHints.isEmpty
        ? 'None yet.'
        : learnedHints.map((hint) => '- $hint').join('\n');
    final json = await _postToOpenAI(
      system:
          'You predict the next words a hospital patient is about to type. '
          'Suggestions must be short (1 to 5 words), plain, and kind. '
          'Use this person\'s questionnaire and past phrases when they fit. '
          'Return a JSON array of 4 to 6 strings only.',
      user: '''
They are writing $where.
Current text: ${currentText.trim().isEmpty ? '(empty)' : currentText.trim()}
${conversationHint == null || conversationHint.trim().isEmpty ? '' : 'The other person just said: ${conversationHint.trim()}\n'}
About this person:
${(personProfile ?? '').trim().isEmpty ? 'No questionnaire yet. Use general, simple hospital language.' : personProfile!.trim()}

Phrases this person has used or chosen before:
$learned

${AppLanguage.instance.suggestionLanguageRule}

Predict likely next words or short phrases they might tap.
''',
      temperature: 0.3,
      maxTokens: 90,
    );
    return _extractFreePhrases(_extractChatCompletionText(json));
  }

  List<String> _extractLabelList(String raw, List<String> allowed) {
    final byKey = <String, String>{
      for (final label in allowed) label.toLowerCase(): label,
    };
    final picked = <String>[];

    void addLabel(String value) {
      final match = byKey[value.trim().toLowerCase()];
      if (match == null) return;
      if (picked.any((label) => label.toLowerCase() == match.toLowerCase())) {
        return;
      }
      picked.add(match);
    }

    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(raw.substring(start, end + 1));
        if (decoded is List) {
          for (final item in decoded) {
            addLabel('$item');
            if (picked.length >= 2) return picked;
          }
        }
      } catch (_) {}
    }

    for (final part in raw.split(RegExp(r'[\n,]'))) {
      addLabel(part.replaceAll(RegExp(r'^[\s\-*"\d.]+|[\s*"\]]+$'), ''));
      if (picked.length >= 2) break;
    }
    return picked;
  }

  List<String> _extractFreePhrases(String raw) {
    final picked = <String>[];

    void addPhrase(String value) {
      final phrase = value
          .replaceAll(RegExp(r'^[\s\-*"\d.\[\]]+|[\s*"\]]+$'), '')
          .replaceAll('"', '')
          .trim();
      if (phrase.isEmpty || phrase.length > 42) return;
      if (phrase.split(RegExp(r'\s+')).length > 6) return;
      if (picked.any((item) => item.toLowerCase() == phrase.toLowerCase())) {
        return;
      }
      picked.add(phrase);
    }

    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(raw.substring(start, end + 1));
        if (decoded is List) {
          for (final item in decoded) {
            addPhrase('$item');
            if (picked.length >= 6) return picked;
          }
        }
      } catch (_) {}
    }

    for (final part in raw.split(RegExp(r'[\n,]'))) {
      addPhrase(part);
      if (picked.length >= 6) break;
    }
    return picked;
  }

  Future<Map<String, dynamic>> _postToOpenAI({
    required String system,
    required String user,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    final body = {
      // Safe default model for Chat Completions
      "model": "gpt-4o-mini",
      "messages": [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
      ],
      "temperature": temperature,
      if (maxTokens != null) "max_tokens": maxTokens,
    };

    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: _headers(),
      body: jsonEncode(body),
    );

    if (kDebugMode) debugPrint("OpenAI status=${res.statusCode}");

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("OpenAI error ${res.statusCode}: ${res.body}");
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  String _extractChatCompletionText(Map<String, dynamic> json) {
    final choices = json["choices"];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final msg = first["message"];
        if (msg is Map) {
          final content = (msg["content"] ?? "").toString().trim();
          return content;
        }
      }
    }
    return "";
  }

  String _formatConversation(List<Map<String, dynamic>> msgs) {
    final sb = StringBuffer();
    for (final m in msgs) {
      final isUser = (m["isUser"] ?? false) == true;
      final text = (m["text"] ?? "").toString().trim();
      if (text.isEmpty) continue;
      sb.writeln(isUser ? "Patient: $text" : "Assistant: $text");
    }
    return sb.toString().trim();
  }
}