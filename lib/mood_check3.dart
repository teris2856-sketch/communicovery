import 'package:flutter/material.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/home_page.dart';
import 'package:swiftspeak/mood_check_service.dart';

class MoodCheck3 extends StatefulWidget {
  const MoodCheck3({
    super.key,
    required this.moodToday,
    required this.stress,
    required this.energy,
    required this.hopefulness,
    required this.confidence,
  });

  final String moodToday;
  final double stress;
  final double energy;
  final double hopefulness;
  final double confidence;

  @override
  State<MoodCheck3> createState() => _MoodCheck3State();
}

class _MoodCheck3State extends State<MoodCheck3> {
  final MoodCheckService _service = MoodCheckService();

  bool _loading = true;
  String _insight = AppLanguage.instance.t('generatingInsight');
  String? _entryId;

  @override
  void initState() {
    super.initState();
    _generateAndSave();
  }

  Future<void> _generateAndSave() async {
    try {
      final insight = await _service.generateInsight(
        moodToday: widget.moodToday,
        stress: widget.stress,
        energy: widget.energy,
        hopefulness: widget.hopefulness,
        confidence: widget.confidence,
      );

      final entryId = await _service.saveMoodEntry(
        moodToday: widget.moodToday,
        stress: widget.stress,
        energy: widget.energy,
        hopefulness: widget.hopefulness,
        confidence: widget.confidence,
        insight: insight,
      );

      if (!mounted) return;
      setState(() {
        _insight = insight;
        _entryId = entryId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _insight = "Failed: $e";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLangBuilder(
      builder: (context, t) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blueAccent,
            title: Text(t('moodResults')),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      t('hereAreResults'),
                      style: const TextStyle(fontSize: 40),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    _buildResultBox(
                      t('yourMoodToday'),
                      AppLanguage.instance.moodLabel(widget.moodToday),
                    ),
                    _buildResultBox(
                      t('yourStressLevel'),
                      widget.stress.toStringAsFixed(1),
                    ),
                    _buildResultBox(
                      t('yourEnergyLevel'),
                      widget.energy.toStringAsFixed(1),
                    ),
                    _buildResultBox(
                      t('yourHopefulnessLevel'),
                      widget.hopefulness.toStringAsFixed(1),
                    ),
                    _buildResultBox(
                      t('yourConfidenceLevel'),
                      widget.confidence.toStringAsFixed(1),
                    ),
                    _buildResultBox(
                      t('aiInsight'),
                      _insight,
                      isInsight: true,
                    ),
                    if (_entryId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          t('savedId', {'id': _entryId!}),
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      child: Text(
                        t('backToHome'),
                        style: const TextStyle(fontSize: 26),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const HomePage()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResultBox(String title, String value, {bool isInsight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          border: Border.all(width: 2),
          color: Colors.blueAccent.shade100,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            if (_loading && isInsight)
              Text(AppLanguage.instance.t('generatingInsight'), style: const TextStyle(fontSize: 24))
            else
              Text(
                value,
                style: TextStyle(fontSize: isInsight ? 24 : 30),
              ),
          ],
        ),
      ),
    );
  }
}