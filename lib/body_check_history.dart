import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:swiftspeak/app_language.dart';
import 'body_check_details1.dart';
import 'home_page.dart';

// Months and years for dropdowns
const List<String> months = <String>[
  'All', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const List<String> years = <String>['All', '2026', '2025', '2024', '2023', '2017', '2013'];

class BodyCheckHistory extends StatefulWidget {
  const BodyCheckHistory({super.key});

  @override
  State<BodyCheckHistory> createState() => _BodyCheckHistoryState();
}

class _BodyCheckHistoryState extends State<BodyCheckHistory> {
  String selectedMonth = 'All';
  String selectedYear = 'All';

  String monthName(int month) {
    // month: 1..12
    return months[month];
  }

  String _formatDate(DateTime dt) {
    // Matches your old style: M/D/YYYY
    return "${dt.month}/${dt.day}/${dt.year}";
  }

  bool _matchesFilters(DateTime dt) {
    final monthMatch = selectedMonth == 'All' || monthName(dt.month) == selectedMonth;
    final yearMatch = selectedYear == 'All' || dt.year.toString() == selectedYear;
    return monthMatch && yearMatch;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _entriesStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // empty stream if not logged in
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('body_checks')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return AppLangBuilder(
      builder: (context, t) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('bodyCheckHistory')),
        backgroundColor: Colors.blueAccent,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
          child: Column(
            children: [
              // Dropdowns
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('body-month-${AppLanguage.instance.code}-$selectedMonth'),
                      initialValue: selectedMonth,
                      decoration: InputDecoration(
                        labelText: t('month'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.blueAccent.withValues(alpha: 0.08),
                      ),
                      selectedItemBuilder: (context) => months
                          .map((month) => Text(
                                AppLanguage.instance.monthLabel(month),
                              ))
                          .toList(),
                      items: months.map((month) {
                        return DropdownMenuItem(
                          value: month,
                          child: Text(AppLanguage.instance.monthLabel(month)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedMonth = value!;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('body-year-${AppLanguage.instance.code}-$selectedYear'),
                      initialValue: selectedYear,
                      decoration: InputDecoration(
                        labelText: t('year'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.blueAccent.withValues(alpha: 0.08),
                      ),
                      selectedItemBuilder: (context) => years
                          .map((year) => Text(
                                AppLanguage.instance.yearLabel(year),
                              ))
                          .toList(),
                      items: years.map((year) {
                        return DropdownMenuItem(
                          value: year,
                          child: Text(AppLanguage.instance.yearLabel(year)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedYear = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // History list (Firebase)
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _entriesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          "Error: ${snapshot.error}",
                          style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];

                    // Map docs -> items with date + entryId, then apply filters
                    final items = docs.map((d) {
                      final data = d.data();
                      final ts = data['createdAt'];
                      DateTime dt;

                      if (ts is Timestamp) {
                        dt = ts.toDate();
                      } else {
                        // fallback if missing/invalid
                        dt = DateTime.fromMillisecondsSinceEpoch(0);
                      }

                      return {
                        'entryId': d.id,
                        'date': _formatDate(dt),
                        'dt': dt,
                      };
                    }).where((item) => _matchesFilters(item['dt'] as DateTime)).toList();

                    if (items.isEmpty) {
                      return Center(
                        child: Text(
                          t('noResultsFound'),
                          style: TextStyle(fontSize: 24, color: Colors.grey[700]),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final entryId = item['entryId'] as String;
                        final dateStr = item['date'] as String;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => BodyCheckDetails1(entryId: entryId),
                                ),
                              );
                            },
                            child: Container(
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.shade100,
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    offset: Offset(2, 2),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  dateStr,
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

              // Back to home button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.home),
                  label: Text(
                    t('backToHome'),
                    style: const TextStyle(fontSize: 24),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => HomePage()),
                    );
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