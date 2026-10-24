import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:swiftspeak/app_keyboard.dart';
import 'package:swiftspeak/login.dart';
import 'package:swiftspeak/typing_prediction.dart';

const _kPlaceholderPatientNames = [
  'Maya Thompson',
  'James Okonkwo',
  'Sofia Alvarez',
  'Liam Chen',
  'Ava Patel',
  'Noah Williams',
  'Harper Kim',
  'Ethan Brooks',
  'Zoe Nguyen',
  'Owen Garcia',
  'Nora Singh',
  'Caleb Foster',
];

const _kPlaceholderLastNames = [
  'Thompson',
  'Okonkwo',
  'Alvarez',
  'Chen',
  'Patel',
  'Williams',
  'Kim',
  'Brooks',
  'Nguyen',
  'Garcia',
  'Singh',
  'Foster',
];

String _placeholderPatientName(int index) {
  return _kPlaceholderPatientNames[index % _kPlaceholderPatientNames.length];
}

String _placeholderLastName(int index) {
  return _kPlaceholderLastNames[index % _kPlaceholderLastNames.length];
}

String _capitalizeNamePart(String word) {
  final trimmed = word.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.contains("'")) {
    return trimmed.split("'").map(_capitalizeNamePart).join("'");
  }
  final letters = trimmed.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.isEmpty) return '';
  return letters[0].toUpperCase() + letters.substring(1).toLowerCase();
}

List<String> _patientNameParts(String raw) {
  var text = raw.trim();
  if (text.contains('@')) {
    text = text.split('@').first;
  }
  text = text.replaceAll(RegExp(r'[._\-]+'), ' ');
  const skip = {'patient', 'user', 'test', 'admin', 'jenay'};
  return text
      .split(RegExp(r'\s+'))
      .map(_capitalizeNamePart)
      .where((part) => part.length >= 2 && !skip.contains(part.toLowerCase()))
      .toList();
}

String _properPatientName({
  required Map<String, dynamic> data,
  required int index,
}) {
  final displayName = (data['displayName'] as String?)?.trim() ?? '';
  final email = (data['email'] as String?)?.trim() ?? '';
  final parts = _patientNameParts(
    displayName.isNotEmpty ? displayName : email,
  );
  final looksLikeJenay = '$displayName $email'.toLowerCase().contains('jenay');
  if (parts.isEmpty || looksLikeJenay) {
    return _placeholderPatientName(index);
  }
  if (parts.length == 1) {
    return '${parts.first} ${_placeholderLastName(index)}';
  }
  return parts.join(' ');
}

List<String> _uniqueStaffPatientTitles(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final used = <String>{};
  final titles = <String>[];
  for (var i = 0; i < docs.length; i++) {
    var title = _properPatientName(data: docs[i].data(), index: i);
    if (!used.add(title)) {
      final first = title.split(RegExp(r'\s+')).first;
      var resolved = false;
      for (var n = 0; n < _kPlaceholderLastNames.length; n++) {
        final candidate = '$first ${_placeholderLastName(i + n + 1)}';
        if (used.add(candidate)) {
          title = candidate;
          resolved = true;
          break;
        }
      }
      if (!resolved) {
        title = _placeholderPatientName(i + used.length);
        used.add(title);
      }
    }
    titles.add(title);
  }
  return titles;
}

String _patientInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

Color _patientAvatarColor(int index) {
  const colors = [
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF6C00),
    Color(0xFF8D6E63),
    Color(0xFF7E57C2),
    Color(0xFF00897B),
    Color(0xFFD81B60),
    Color(0xFF3949AB),
  ];
  return colors[index % colors.length];
}

String _formatPatientCheckDate(dynamic createdAt) {
  if (createdAt is Timestamp) {
    final d = createdAt.toDate();
    return '${d.month}/${d.day}/${d.year}';
  }
  return 'Unknown date';
}

String _formatShortDate(DateTime d) =>
    '${d.month}/${d.day}/${d.year}';

/// Matches messages saved from [NewChat] when the patient requests an AI recommendation.
const String _kPatientChatAiRecPrefix = 'AI Recommendation:\n';

String _painLevelFromValue(dynamic v) {
  int? n;
  if (v is int) {
    n = v;
  } else if (v is num) {
    n = v.toInt();
  }
  switch (n) {
    case 1:
      return 'Low';
    case 2:
      return 'Moderate';
    case 3:
      return 'High';
    default:
      return 'None';
  }
}

Map<String, String> _patientBodyPainMerge(Map<String, dynamic> data) {
  final front = (data['front'] as Map?)?.cast<String, dynamic>() ?? {};
  final back = (data['back'] as Map?)?.cast<String, dynamic>() ?? {};
  final side = (data['side'] as Map?)?.cast<String, dynamic>() ?? {};
  final merged = <String, String>{};
  void addSide(Map<String, dynamic> m) {
    m.forEach((k, v) {
      final label = _painLevelFromValue(v);
      if (label != 'None') {
        merged[k] = label;
      }
    });
  }

  addSide(front);
  addSide(back);
  addSide(side);
  return merged;
}

String _patientBodyRiskLevel(Map<String, dynamic> data) {
  int m = 0;
  final max = data['maxPain'];
  if (max is int) {
    m = max;
  } else if (max is num) {
    m = max.toInt();
  } else {
    for (final label in _patientBodyPainMerge(data).values) {
      if (label == 'High') {
        m = 3;
      } else if (label == 'Moderate' && m < 2) {
        m = 2;
      } else if (label == 'Low' && m < 1) {
        m = 1;
      }
    }
  }
  if (m >= 3) {
    return 'HIGH';
  }
  if (m >= 2) {
    return 'MODERATE';
  }
  return 'LOW';
}

Color _patientBodyRiskColor(String risk) {
  switch (risk) {
    case 'HIGH':
      return Colors.red;
    case 'MODERATE':
      return Colors.orange;
    default:
      return Colors.green;
  }
}

String _patientMoodNum(dynamic n) {
  if (n is num) {
    return n.toStringAsFixed(1);
  }
  return '—';
}

String _patientBodySummaryForClinical(Map<String, dynamic> data) {
  final merged = _patientBodyPainMerge(data);
  if (merged.isEmpty) {
    return 'No pain areas reported.';
  }
  final parts =
      merged.entries.map((e) => '${e.key}: ${e.value}').take(5).join('; ');
  return merged.length > 5 ? '$parts…' : parts;
}

String _patientMoodSummaryForClinical(Map<String, dynamic> d) {
  final mood = d['moodToday']?.toString() ?? '—';
  return 'Mood: $mood. Stress ${_patientMoodNum(d['stress'])}/5, '
      'energy ${_patientMoodNum(d['energy'])}/5, '
      'hopefulness ${_patientMoodNum(d['hopefulness'])}/5, '
      'confidence ${_patientMoodNum(d['confidence'])}/5.';
}

Future<Map<String, String>> _loadPatientClinicalSnapshot(String patientUid) async {
  final db = FirebaseFirestore.instance;
  final bodySnap = await db
      .collection('users')
      .doc(patientUid)
      .collection('body_checks')
      .orderBy('createdAt', descending: true)
      .limit(1)
      .get();
  final moodSnap = await db
      .collection('users')
      .doc(patientUid)
      .collection('mood_checks')
      .orderBy('createdAt', descending: true)
      .limit(1)
      .get();

  var body = 'No body checks yet.';
  if (bodySnap.docs.isNotEmpty) {
    body = _patientBodySummaryForClinical(bodySnap.docs.first.data());
  }
  var mood = 'No mood checks yet.';
  if (moodSnap.docs.isNotEmpty) {
    mood = _patientMoodSummaryForClinical(moodSnap.docs.first.data());
  }
  return {'body': body, 'mood': mood};
}

void main() {
  runApp(const MyApp());
}

// ===== MAIN APP =====
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: StaffHomePage());
  }
}

// ===== BLUE BOX =====
Widget buildBlueBox(String title, List<Widget> children) {
  return Center(
    child: SizedBox(
      width: 350,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.blueAccent.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blueAccent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    ),
  );
}

// ===== ACTION BOX =====
Widget buildActionBox({
  required String title,
  required IconData icon,
  required VoidCallback onTap,
}) {
  return Center(
    child: SizedBox(
      width: 350,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.blueAccent.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blueAccent, width: 2),
          ),
          child: Row(
            children: [
              Icon(icon, size: 30, color: Colors.blueAccent),
              const SizedBox(width: 15),
              Text(title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    ),
  );
}

// ===== DATE BUBBLE =====
Widget buildDateBubble(String date, VoidCallback onTap) {
  return Center(
    child: SizedBox(
      width: 350,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.blueAccent, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

// ===== STATUS COLOR =====
Color getStatusColor(String status) {
  switch (status.toLowerCase()) {
    case "stable":
      return Colors.green;
    case "moderate":
      return Colors.orange;
    case "critical":
      return Colors.red;
    default:
      return Colors.black;
  }
}

// ===== HOME PAGE =====
class StaffHomePage extends StatelessWidget {
  const StaffHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Stroke Patient Dashboard",
            style: TextStyle(fontSize: 22)),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'patient')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load patients.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No patients yet. New accounts that choose '
                        '"Patient" during sign up will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  );
                }
                final titles = _uniqueStaffPatientTitles(docs);
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();
                    final uid = doc.id;
                    final title = titles[i];
                    final email = (data['email'] as String?)?.trim();
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _patientAvatarColor(i),
                          foregroundColor: Colors.white,
                          child: Text(
                            _patientInitials(title),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(fontSize: 18),
                        ),
                        subtitle: Text(
                          (email != null && email.isNotEmpty) ? email : uid,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PatientDashboard(
                                patientUid: uid,
                                patientName: title,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  await TypingPredictionStore.instance.reset();
                  await FirebaseAuth.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const Login()),
                    (route) => false,
                  );
                },
                child: const Text(
                  'Sign out',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== PATIENT DASHBOARD =====
class PatientDashboard extends StatefulWidget {
  final String patientUid;
  final String patientName;

  const PatientDashboard({
    super.key,
    required this.patientUid,
    required this.patientName,
  });

  @override
  State<PatientDashboard> createState() =>
      _PatientDashboardState();
}

class _PatientDashboardState
    extends State<PatientDashboard> {
  String currentView = "main";

  Map<String, dynamic>? _bodyDetailData;
  String? _bodyDetailLabel;

  Map<String, dynamic>? _moodDetailData;
  String? _moodDetailLabel;

  Future<Map<String, String>>? _clinicalSnapshotFuture;

  final TextEditingController aiController =
  TextEditingController();
  bool aiLoading = false;

  /// Latest patient chat AI recommendation text (from Firestore); staff may edit a copy here.
  final TextEditingController _patientAiRecController =
      TextEditingController();
  /// Timestamp of the newest stored `AI Recommendation:` message, if any.
  DateTime? _patientRecAt;
  final List<String> _aiEditVersionHistory = [];

  String get patientDisplayName {
    final raw = widget.patientName;
    if (raw.contains(': ')) {
      return raw.split(': ').last;
    }
    final at = raw.indexOf('@');
    if (at > 0) {
      return raw.substring(0, at);
    }
    return raw;
  }

  Future<void> loadPatientChatAiRecommendation() async {
    setState(() => aiLoading = true);
    try {
      final db = FirebaseFirestore.instance;
      final uid = widget.patientUid;
      final chatsSnap = await db
          .collection('users')
          .doc(uid)
          .collection('chats')
          .orderBy('updatedAt', descending: true)
          .get();

      String bestText = '';
      DateTime? bestAt;

      for (final chatDoc in chatsSnap.docs) {
        final messagesSnap = await db
            .collection('users')
            .doc(uid)
            .collection('chats')
            .doc(chatDoc.id)
            .collection('messages')
            .orderBy('createdAt', descending: true)
            .limit(100)
            .get();

        for (final m in messagesSnap.docs) {
          final data = m.data();
          if ((data['isUser'] ?? false) == true) continue;
          final text = (data['text'] ?? '').toString();
          if (!text.startsWith(_kPatientChatAiRecPrefix)) continue;
          final body = text.substring(_kPatientChatAiRecPrefix.length).trim();
          final ts = data['createdAt'];
          DateTime? dt;
          if (ts is Timestamp) dt = ts.toDate();
          if (dt == null) continue;
          if (bestAt == null || dt.isAfter(bestAt)) {
            bestAt = dt;
            bestText = body;
          }
          break;
        }
      }

      if (!mounted) return;
      if (bestText.isEmpty) {
        _patientAiRecController.text =
            'No patient chat recommendation yet. It appears after the patient opens AI Chatbot and taps AI Recommendation.';
      } else {
        _patientAiRecController.text = bestText;
      }
      _patientRecAt = bestAt;
    } catch (e) {
      if (!mounted) return;
      _patientAiRecController.text =
          'Could not load recommendations from chat: $e';
      _patientRecAt = null;
    } finally {
      if (mounted) setState(() => aiLoading = false);
    }
  }

  @override
  void dispose() {
    aiController.dispose();
    _patientAiRecController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const status = "Stable";

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patientName,
            style: const TextStyle(fontSize: 22)),
        backgroundColor: Colors.blueAccent,
        leading: currentView != "main"
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              if (currentView == "bodyDetails") {
                currentView = "bodyHistory";
              } else if (currentView ==
                  "moodDetails") {
                currentView = "moodHistory";
              } else if (currentView ==
                  "aiEditor") {
                currentView = "ai";
              } else {
                currentView = "main";
              }
            });
          },
        )
            : null,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildView(status),
        ),
      ),
    );
  }

  Widget _buildView(String status) {
    switch (currentView) {

      case "main":
        return Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            buildBlueBox("Patient Information", [
              Text(
                "Stroke Status: $status",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: getStatusColor(status),
                ),
              ),
              const SizedBox(height: 8),
              const Text("Last Check: 2 hours ago",
                  style: TextStyle(fontSize: 18)),
              const Text("Assigned Nurse: TBD",
                  style: TextStyle(fontSize: 18)),
            ]),
            buildActionBox(
              title: "Body Check",
              icon: Icons.health_and_safety,
              onTap: () {
                setState(
                        () => currentView = "bodyHistory");
              },
            ),
            buildActionBox(
              title: "Mood Check",
              icon: Icons.mood,
              onTap: () {
                setState(
                        () => currentView = "moodHistory");
              },
            ),
            buildActionBox(
              title: "AI Assistant",
              icon: Icons.smart_toy,
              onTap: () async {
                setState(() => currentView = "ai");
                await loadPatientChatAiRecommendation();
              },
            ),
          ],
        );

      case "bodyHistory":
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.patientUid)
              .collection('body_checks')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Body Check History",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (snapshot.hasError)
                  Text(
                    "Error: ${snapshot.error}",
                    style: const TextStyle(fontSize: 16),
                  ),
                if (snapshot.connectionState != ConnectionState.waiting &&
                    !snapshot.hasError &&
                    (snapshot.data?.docs.isEmpty ?? true))
                  const Text(
                    "No body check records yet.",
                    style: TextStyle(fontSize: 18),
                  ),
                if (snapshot.connectionState != ConnectionState.waiting &&
                    !snapshot.hasError &&
                    (snapshot.data?.docs.isNotEmpty ?? false))
                  ...snapshot.data!.docs.map((d) {
                    final data = d.data();
                    final label = _formatPatientCheckDate(data['createdAt']);
                    return buildDateBubble(label, () {
                      setState(() {
                        _bodyDetailData = Map<String, dynamic>.from(data);
                        _bodyDetailLabel = label;
                        currentView = "bodyDetails";
                      });
                    });
                  }),
              ],
            );
          },
        );

      case "bodyDetails":
        final bodyData = _bodyDetailData;
        final bodyLabel = _bodyDetailLabel ?? '—';
        if (bodyData == null) {
          return const Text(
            "Choose an entry from Body Check History.",
            style: TextStyle(fontSize: 18),
          );
        }
        final merged = _patientBodyPainMerge(bodyData);
        final low = bodyData['countLow'] ?? 0;
        final moderate = bodyData['countModerate'] ?? 0;
        final high = bodyData['countHigh'] ?? 0;
        final risk = _patientBodyRiskLevel(bodyData);
        final riskColor = _patientBodyRiskColor(risk);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildBlueBox("Summary for $bodyLabel", [
              Text(
                "Body areas with pain: ${merged.length}",
                style: const TextStyle(fontSize: 18),
              ),
              Text(
                "Low / moderate / high severity counts: $low / $moderate / $high",
                style: const TextStyle(fontSize: 18),
              ),
            ]),
            buildBlueBox("Pain areas", [
              if (merged.isEmpty)
                const Text(
                  "No pain areas recorded for this check.",
                  style: TextStyle(fontSize: 18),
                )
              else
                ...merged.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      "• ${e.key}: ${e.value}",
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
            ]),
            buildBlueBox("AI Risk Assessment", [
              Text(
                "Risk level: $risk",
                style: TextStyle(
                  color: riskColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ]),
          ],
        );

      case "moodHistory":
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.patientUid)
              .collection('mood_checks')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Mood Check History",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (snapshot.hasError)
                  Text(
                    "Error: ${snapshot.error}",
                    style: const TextStyle(fontSize: 16),
                  ),
                if (snapshot.connectionState != ConnectionState.waiting &&
                    !snapshot.hasError &&
                    (snapshot.data?.docs.isEmpty ?? true))
                  const Text(
                    "No mood check records yet.",
                    style: TextStyle(fontSize: 18),
                  ),
                if (snapshot.connectionState != ConnectionState.waiting &&
                    !snapshot.hasError &&
                    (snapshot.data?.docs.isNotEmpty ?? false))
                  ...snapshot.data!.docs.map((d) {
                    final data = d.data();
                    final label = _formatPatientCheckDate(data['createdAt']);
                    return buildDateBubble(label, () {
                      setState(() {
                        _moodDetailData = Map<String, dynamic>.from(data);
                        _moodDetailLabel = label;
                        currentView = "moodDetails";
                      });
                    });
                  }),
              ],
            );
          },
        );

      case "moodDetails":
        final moodData = _moodDetailData;
        final moodLabel = _moodDetailLabel ?? '—';
        if (moodData == null) {
          return const Text(
            "Choose an entry from Mood Check History.",
            style: TextStyle(fontSize: 18),
          );
        }
        final insight = moodData['insight']?.toString() ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildBlueBox("Details for $moodLabel", [
              Text(
                "Mood today: ${moodData['moodToday'] ?? '—'}",
                style: const TextStyle(fontSize: 18),
              ),
              Text(
                "Stress: ${_patientMoodNum(moodData['stress'])}/5",
                style: const TextStyle(fontSize: 18),
              ),
              Text(
                "Energy: ${_patientMoodNum(moodData['energy'])}/5",
                style: const TextStyle(fontSize: 18),
              ),
              Text(
                "Hopefulness: ${_patientMoodNum(moodData['hopefulness'])}/5",
                style: const TextStyle(fontSize: 18),
              ),
              Text(
                "Confidence: ${_patientMoodNum(moodData['confidence'])}/5",
                style: const TextStyle(fontSize: 18),
              ),
            ]),
            buildBlueBox("AI insight", [
              Text(
                insight.isEmpty ? "No insight stored for this entry." : insight,
                style: const TextStyle(fontSize: 18),
              ),
            ]),
          ],
        );

      case "ai":
        final name = patientDisplayName;
        final aiTitle = _patientRecAt != null
            ? "$name — Patient chat AI recommendation · ${_formatShortDate(_patientRecAt!)}"
            : "$name — Patient chat AI recommendation";

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  currentView = "aiEditor";
                  _clinicalSnapshotFuture =
                      _loadPatientClinicalSnapshot(widget.patientUid);
                });
              },
              child: buildBlueBox(
                  aiTitle, [
                aiLoading
                    ? const CircularProgressIndicator()
                    : AbsorbPointer(
                  child: TextField(
                    controller: _patientAiRecController,
                    maxLines: null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        );

      case "aiEditor":
        final controller = _patientAiRecController;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<Map<String, String>>(
              future: _clinicalSnapshotFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return buildBlueBox("Clinical Snapshot", [
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ]);
                }
                if (snap.hasError) {
                  return buildBlueBox("Clinical Snapshot", [
                    Text(
                      "Could not load checks: ${snap.error}",
                      style: const TextStyle(fontSize: 18),
                    ),
                  ]);
                }
                final bodyLine = snap.data?['body'] ?? '—';
                final moodLine = snap.data?['mood'] ?? '—';
                return buildBlueBox("Clinical Snapshot", [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 18, color: Colors.black),
                      children: [
                        TextSpan(
                          text: "Status: ",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: "Stable"),
                      ],
                    ),
                  ),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 18, color: Colors.black),
                      children: [
                        const TextSpan(
                          text: "Latest body check: ",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: bodyLine),
                      ],
                    ),
                  ),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 18, color: Colors.black),
                      children: [
                        const TextSpan(
                          text: "Latest mood check: ",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: moodLine),
                      ],
                    ),
                  ),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 18, color: Colors.black),
                      children: [
                        TextSpan(
                          text: "AI reasoning: ",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text:
                              "Summarized from the patient's most recent submitted body and mood entries.",
                        ),
                      ],
                    ),
                  ),
                ]);
              },
            ),
            buildBlueBox("Edit Recommendation", [
              AppKeyboardField(
                controller: controller,
                maxLines: null,
                enableTidyUp: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _aiEditVersionHistory.insert(0, controller.text);
                  });
                },
                child: const Text("Save Version"),
              ),
            ]),
            const SizedBox(height: 15),
            buildBlueBox("Version History", [
              ..._aiEditVersionHistory.map((version) {
                return Padding(
                  padding:
                  const EdgeInsets.symmetric(vertical: 4),
                  child: Text("• $version",
                      style: const TextStyle(fontSize: 16)),
                );
              }),
            ]),
          ],
        );

      default:
        return const SizedBox();
    }
  }
}