import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:swiftspeak/app_language.dart';
import 'mood_details1.dart';
import 'home_page.dart';

const List<String> months = <String>[
  'All', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const List<String> years = <String>['All', '2026', '2025', '2024', '2023', '2022', '2021'];

class MoodCheck4 extends StatefulWidget {
  const MoodCheck4({super.key});

  @override
  State<MoodCheck4> createState() => _MoodCheck4State();
}

class _MoodCheck4State extends State<MoodCheck4> {
  String selectedMonth = 'All';
  String selectedYear = 'All';

  String _monthName(int month) => months[month];

  bool _matchesFilters(DateTime dt) {
    final monthOk = selectedMonth == 'All' || _monthName(dt.month) == selectedMonth;
    final yearOk = selectedYear == 'All' || dt.year.toString() == selectedYear;
    return monthOk && yearOk;
  }

  @override
  Widget build(BuildContext context) {
    return AppLangBuilder(
      builder: (context, t) {
        final user = FirebaseAuth.instance.currentUser;

        if (user == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(t('moodHistoryTitle')),
              backgroundColor: Colors.blueAccent,
              centerTitle: true,
            ),
            body: Center(
              child: Text(t('pleaseLogIn'), style: const TextStyle(fontSize: 22)),
            ),
          );
        }

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mood_checks')
        .orderBy('createdAt', descending: true);

        return Scaffold(
      appBar: AppBar(
        title: Text(t('moodHistoryTitle')),
        backgroundColor: Colors.blueAccent,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('mood-month-${AppLanguage.instance.code}-$selectedMonth'),
                      initialValue: selectedMonth,
                      decoration: InputDecoration(
                        labelText: t('month'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.blueAccent.withValues(alpha: 0.08),
                      ),
                      selectedItemBuilder: (context) => months
                          .map((m) => Text(AppLanguage.instance.monthLabel(m)))
                          .toList(),
                      items: months
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(AppLanguage.instance.monthLabel(m)),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => selectedMonth = value!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('mood-year-${AppLanguage.instance.code}-$selectedYear'),
                      initialValue: selectedYear,
                      decoration: InputDecoration(
                        labelText: t('year'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.blueAccent.withValues(alpha: 0.08),
                      ),
                      selectedItemBuilder: (context) => years
                          .map((y) => Text(AppLanguage.instance.yearLabel(y)))
                          .toList(),
                      items: years
                          .map((y) => DropdownMenuItem(
                                value: y,
                                child: Text(AppLanguage.instance.yearLabel(y)),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => selectedYear = value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: query.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(child: Text("Error: ${snap.error}", style: const TextStyle(fontSize: 18)));
                    }

                    final docs = snap.data?.docs ?? [];

                    // Filter by month/year (client-side)
                    final filtered = docs.where((d) {
                      final ts = d.data()['createdAt'];
                      if (ts is Timestamp) {
                        return _matchesFilters(ts.toDate());
                      }
                      // if serverTimestamp hasn’t resolved yet, show it anyway
                      return true;
                    }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(t('noResultsFound'), style: TextStyle(fontSize: 24, color: Colors.grey[700])),
                      );
                    }

                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final doc = filtered[index];
                        final data = doc.data();
                        final ts = data['createdAt'];
                        DateTime? dt;
                        if (ts is Timestamp) dt = ts.toDate();

                        final titleDate = dt == null
                            ? t('justNow')
                            : "${dt.month}/${dt.day}/${dt.year}";

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MoodDetails1(entryId: doc.id),
                                ),
                              );
                            },
                            child: Container(
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.shade100,
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    offset: Offset(2, 2),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  titleDate,
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueAccent.shade700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.home),
                  label: Text(t('backToHome'), style: const TextStyle(fontSize: 24)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => HomePage()));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }
}