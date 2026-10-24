import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/home_page.dart';

class BodyCheckDetails1 extends StatefulWidget {
  const BodyCheckDetails1({super.key, required this.entryId});

  final String entryId;

  @override
  State<BodyCheckDetails1> createState() => _BodyCheckDetails1State();
}

class _BodyCheckDetails1State extends State<BodyCheckDetails1> {
  Map<String, String> painData = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  String _levelToText(int v) {
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          isLoading = false;
          painData = {};
        });
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('body_checks')
          .doc(widget.entryId)
          .get();

      if (!doc.exists) {
        setState(() {
          isLoading = false;
          painData = {};
        });
        return;
      }

      final data = doc.data() ?? {};

      final frontRaw = (data['front'] as Map?) ?? {};
      final backRaw = (data['back'] as Map?) ?? {};
      final sideRaw = (data['side'] as Map?) ?? {};

      final frontPain = Map<String, dynamic>.from(frontRaw);
      final backPain = Map<String, dynamic>.from(backRaw);
      final sidePain = Map<String, dynamic>.from(sideRaw);

      final combined = <String, dynamic>{
        ...frontPain,
        ...backPain,
        ...sidePain,
      };

      final Map<String, String> mapped = {};
      combined.forEach((key, value) {
        final intLevel = (value as num).toInt();
        if (intLevel > 0) {
          mapped[key] = _levelToText(intLevel);
        }
      });

      setState(() {
        painData = mapped;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        painData = {};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLanguage.instance.t('failedLoadBody', {'error': '$e'}))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLangBuilder(
      builder: (context, t) {
        if (isLoading) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.blueAccent,
              title: Text(t('bodyCheckResults')),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blueAccent,
            title: Text(t('bodyCheckResults')),
          ),
          body: Center(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Text(
                  t('painSummary'),
                  style: const TextStyle(fontSize: 32),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (painData.isEmpty) buildInfoContainer(t('noPainToday')),
                ...painData.entries.map(
                  (entry) => buildPainContainer(entry.key, entry.value),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const HomePage()),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
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