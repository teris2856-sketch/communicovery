import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/home_page.dart';

class MoodDetails1 extends StatefulWidget {
  const MoodDetails1({super.key, required this.entryId});

  final String entryId;

  @override
  State<MoodDetails1> createState() => _MoodDetails1State();
}

class _MoodDetails1State extends State<MoodDetails1> {
  bool isLoading = true;
  Map<String, dynamic> entry = {};
  String error = "";

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  Future<void> _loadEntry() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          isLoading = false;
          error = AppLanguage.instance.t('notLoggedIn');
        });
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mood_checks')
          .doc(widget.entryId)
          .get();

      final data = doc.data();
      if (data == null) {
        setState(() {
          isLoading = false;
          error = AppLanguage.instance.t('entryNotFound');
        });
        return;
      }

      setState(() {
        entry = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        error = e.toString();
      });
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
              title: Text(t('moodResults')),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (error.isNotEmpty) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.blueAccent,
              title: Text(t('moodResults')),
            ),
            body: Center(child: Text(error, style: const TextStyle(fontSize: 18))),
          );
        }

        final moodToday = (entry['moodToday'] ?? '').toString();
        final stress = (entry['stress'] ?? 0).toString();
        final energy = (entry['energy'] ?? 0).toString();
        final hope = (entry['hopefulness'] ?? 0).toString();
        final conf = (entry['confidence'] ?? 0).toString();
        final insight = (entry['insight'] ?? '').toString();

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blueAccent,
            title: Text(t('moodResults')),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Text(t('hereAreResults'), style: const TextStyle(fontSize: 36), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  buildStatContainer(t('yourMoodToday'), AppLanguage.instance.moodLabel(moodToday)),
                  buildStatContainer(t('yourStressLevel'), stress),
                  buildStatContainer(t('yourEnergyLevel'), energy),
                  buildStatContainer(t('yourHopefulnessLevel'), hope),
                  buildStatContainer(t('yourConfidenceLevel'), conf),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(width: 2),
                      color: Colors.blueAccent.shade100,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Column(
                      children: [
                        Text(t('aiInsight'), style: const TextStyle(fontSize: 26), textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        Text(
                          insight.isEmpty ? t('noInsightSaved') : insight,
                          style: const TextStyle(fontSize: 22),
                          textAlign: TextAlign.center,
                          softWrap: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (context) => HomePage()));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Text(t('backToHome'), style: const TextStyle(fontSize: 24)),
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

  Widget buildStatContainer(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(width: 2),
          color: Colors.blueAccent.shade100,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 24), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 24), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}