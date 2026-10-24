import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:swiftspeak/app_keyboard.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/home_page.dart';
import 'package:swiftspeak/staff_home_page.dart';
import 'package:swiftspeak/typing_prediction.dart';

const surveyQuestionLabels = <String, String>{
  'pets': 'Pets',
  'fun': 'For fun',
  'people': 'People',
  'comfort': 'What helps',
  'food': 'Food and drink',
  'home': 'Home and care',
  'names': 'Names and nicknames',
  'talk': 'Things they want to say',
  'routine': 'Usual day',
  'more': 'Anything else',
};

class WelcomeSurveyPage extends StatefulWidget {
  const WelcomeSurveyPage({
    super.key,
    required this.role,
    this.updateExisting = false,
  });

  final String role;
  final bool updateExisting;

  @override
  State<WelcomeSurveyPage> createState() => _WelcomeSurveyPageState();
}

class _WelcomeSurveyPageState extends State<WelcomeSurveyPage> {
  static const _questions = <_SurveyQuestion>[
    _SurveyQuestion(id: 'pets'),
    _SurveyQuestion(id: 'fun'),
    _SurveyQuestion(id: 'people'),
    _SurveyQuestion(id: 'comfort'),
    _SurveyQuestion(id: 'food'),
    _SurveyQuestion(id: 'home'),
    _SurveyQuestion(id: 'names'),
    _SurveyQuestion(id: 'talk'),
    _SurveyQuestion(id: 'routine'),
    _SurveyQuestion(id: 'more'),
  ];

  late final Map<String, TextEditingController> _answers = {
    for (final question in _questions)
      question.id: TextEditingController(),
  };

  var _index = 0;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.updateExisting) {
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final raw = doc.data()?['survey'];
      if (raw is! Map || !mounted) return;
      final data = Map<String, dynamic>.from(raw);
      setState(() {
        for (final question in _questions) {
          _answers[question.id]!.text = _existingText(data, question.id);
        }
      });
    } catch (_) {}
  }

  String _existingText(Map<String, dynamic> data, String id) {
    final value = data[id];
    if (value is List) {
      return value.map((item) => '$item'.trim()).where((item) => item.isNotEmpty).join(', ');
    }
    if (id == 'pets') {
      final pets = '${data['pets'] ?? ''}'.trim();
      final note = '${data['petsNote'] ?? ''}'.trim();
      if (note.isNotEmpty) {
        return pets.isEmpty || pets == 'Yes' ? note : '$pets. $note';
      }
    }
    if (id == 'fun') {
      final extra = '${data['funNote'] ?? ''}'.trim();
      final main = value is List
          ? value.map((item) => '$item'.trim()).where((item) => item.isNotEmpty).join(', ')
          : '${value ?? ''}'.trim();
      if (extra.isNotEmpty && main.isNotEmpty) return '$main. $extra';
      if (extra.isNotEmpty) return extra;
      return main;
    }
    if (id == 'more') {
      final notes = '${data['notes'] ?? ''}'.trim();
      if (notes.isNotEmpty) return notes;
    }
    return '${value ?? ''}'.trim();
  }

  @override
  void dispose() {
    for (final controller in _answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  _SurveyQuestion get _current => _questions[_index];

  bool get _isLast => _index == _questions.length - 1;

  Future<void> _finish({required bool skipped}) async {
    if (_saving) return;
    setState(() => _saving = true);
    AppKeyboardController.instance.hide();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final survey = <String, dynamic>{};
      if (!skipped) {
        for (final question in _questions) {
          final text = _answers[question.id]!.text.trim();
          if (text.isNotEmpty) survey[question.id] = text;
        }
      }

      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {
            'surveyCompleted': true,
            'surveyCompletedAt': FieldValue.serverTimestamp(),
            if (survey.isNotEmpty) 'survey': survey,
          },
          SetOptions(merge: true),
        );
        if (survey.isNotEmpty) {
          await TypingPredictionStore.instance.applySurvey(survey);
          AppKeyboardController.instance.refreshPredictions();
        }
      } catch (_) {
        // Still let them into the app if saving fails.
      }
    }

    if (!mounted) return;
    if (widget.updateExisting) {
      Navigator.pop(context, true);
      return;
    }
    final home = widget.role == 'staff'
        ? const StaffHomePage()
        : const HomePage();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => home),
      (route) => false,
    );
  }

  void _next() {
    AppKeyboardController.instance.hide();
    if (_isLast) {
      _finish(skipped: false);
      return;
    }
    setState(() => _index += 1);
  }

  void _back() {
    AppKeyboardController.instance.hide();
    if (_index == 0) return;
    setState(() => _index -= 1);
  }

  @override
  Widget build(BuildContext context) {
    final question = _current;
    final progress = (_index + 1) / _questions.length;

    return AppLangBuilder(
      builder: (context, t) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        automaticallyImplyLeading: widget.updateExisting,
        title: Text(t('aLittleAboutYou')),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    if (widget.updateExisting) {
                      Navigator.pop(context, false);
                      return;
                    }
                    _finish(skipped: true);
                  },
            child: Text(
              widget.updateExisting ? t('cancel') : t('skip'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
              color: Colors.blueAccent,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t('questionNofM', {
                        'n': '${_index + 1}',
                        'm': '${_questions.length}',
                      }),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t('survey_${question.id}_title'),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t('survey_${question.id}_hint'),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blueGrey.shade700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppKeyboardField(
                      controller: _answers[question.id],
                      minLines: 4,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: t('typeAsMuch'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  if (_index > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _back,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(t('back'), style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  if (_index > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        _saving
                            ? t('saving')
                            : _isLast
                                ? t('finish')
                                : t('next'),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

class _SurveyQuestion {
  const _SurveyQuestion({required this.id});

  final String id;
}
