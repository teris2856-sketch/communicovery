import 'package:flutter/material.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/home_page.dart';
import 'package:swiftspeak/body_check_service.dart';

class BodyCheckResults extends StatefulWidget {
  final String entryId;

  const BodyCheckResults({
    super.key,
    required this.entryId,
  });

  @override
  State<BodyCheckResults> createState() => _BodyCheckResultsState();
}

class _BodyCheckResultsState extends State<BodyCheckResults> {
  final BodyCheckService _service = BodyCheckService();

  bool _loading = true;
  String? _error;

  // This matches your existing UI logic (String -> "Low/Moderate/High")
  final Map<String, String> painData = {};

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  String _levelLabel(int v) {
    switch (v) {
      case 1:
        return "Low";
      case 2:
        return "Moderate";
      case 3:
        return "High";
      default:
        return "None";
    }
  }

  Future<void> _loadEntry() async {
    try {
      final snap = await _service.getEntry(widget.entryId);

      final data = snap.data(); // ✅ THIS is the map
      if (data == null) {
        setState(() {
          _error = AppLanguage.instance.t('noDataFound');
          _loading = false;
        });
        return;
      }

      // Firestore structure you showed:
      // front: { Chest: 2, LeftHand: 1, ... }
      // back:  { LowerBack: 3, ... }
      final front = (data['front'] as Map?)?.cast<String, dynamic>() ?? {};
      final back = (data['back'] as Map?)?.cast<String, dynamic>() ?? {};
      final side = (data['side'] as Map?)?.cast<String, dynamic>() ?? {};

      final merged = <String, String>{};

      void addSide(Map<String, dynamic> m) {
        m.forEach((k, v) {
          if (v is int) {
            if (v > 0) merged[k] = _levelLabel(v);
          } else if (v is num) {
            final vi = v.toInt();
            if (vi > 0) merged[k] = _levelLabel(vi);
          }
        });
      }

      addSide(front);
      addSide(back);
      addSide(side);

      setState(() {
        painData
          ..clear()
          ..addAll(merged);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
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
            title: Text(t('bodyCheckResults')),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    t('painSummary'),
                    style: const TextStyle(fontSize: 32),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (_loading) buildInfoContainer(t('loading')),
                  if (!_loading && _error != null)
                    buildInfoContainer(_error!),
                  if (!_loading && _error == null && painData.isEmpty)
                    buildInfoContainer(t('noPainToday')),
                  if (!_loading && _error == null && painData.isNotEmpty)
                    ...painData.entries.map(
                      (entry) => buildPainContainer(entry.key, entry.value),
                    ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const HomePage()),
                        (route) => false,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Text(
                        t('backToHome'),
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildPainContainer(String bodyPart, String painLevel) {
    Color painColor;

    switch (painLevel) {
      case "Low":
        painColor = Colors.green;
        break;
      case "Moderate":
        painColor = Colors.orange;
        break;
      case "High":
        painColor = Colors.red;
        break;
      default:
        painColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(width: 2),
          color: painColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          children: [
            Text(
              AppLanguage.instance.bodyPartLabel(bodyPart),
              style: const TextStyle(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              AppLanguage.instance.t(
                'painLevelColon',
                {'level': AppLanguage.instance.painLabel(painLevel)},
              ),
              style: TextStyle(
                fontSize: 22,
                color: painColor,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildInfoContainer(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(width: 2),
        color: Colors.blueAccent.shade100,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 22),
        textAlign: TextAlign.center,
      ),
    );
  }
}