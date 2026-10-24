import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:swiftspeak/app_keyboard.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/welcome_survey_page.dart';

class PatientProfilePage extends StatefulWidget {
  const PatientProfilePage({super.key});

  @override
  State<PatientProfilePage> createState() => _PatientProfilePageState();
}

class _PatientProfilePageState extends State<PatientProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _nameController = TextEditingController();

  bool _loading = true;
  bool _savingName = false;
  Map<String, dynamic> _survey = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    String name = user.displayName ?? '';
    Map<String, dynamic> survey = {};
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final fromDb = doc.data()?['displayName'] as String?;
      if (fromDb != null && fromDb.isNotEmpty) {
        name = fromDb;
      }
      final raw = doc.data()?['survey'];
      if (raw is Map) {
        survey = Map<String, dynamic>.from(raw);
      }
    } catch (_) {
      // Keep Auth display name
    }

    if (!mounted) return;
    setState(() {
      _nameController.text = name;
      _survey = survey;
      _loading = false;
    });
  }

  Future<void> _saveDisplayName() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final trimmed = _nameController.text.trim();
    setState(() => _savingName = true);
    try {
      await user.updateDisplayName(trimmed.isEmpty ? null : trimmed);
      await user.reload();
      await _firestore.collection('users').doc(user.uid).set(
        {
          'displayName': trimmed.isEmpty ? FieldValue.delete() : trimmed,
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name updated')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Could not update name')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  String _surveyValue(dynamic value) {
    if (value is List) {
      return value.map((item) => '$item').where((item) => item.isNotEmpty).join(', ');
    }
    return '$value'.trim();
  }

  List<Widget> _surveyTiles() {
    final labels = <String, String>{
      ...surveyQuestionLabels,
      'petsNote': 'About their pets',
      'funNote': 'Other things they enjoy',
      'notes': 'Other notes',
    };
    final tiles = <Widget>[];
    for (final entry in labels.entries) {
      final text = _surveyValue(_survey[entry.key]);
      if (text.isEmpty) continue;
      tiles.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _InfoTile(label: entry.value, value: text),
        ),
      );
    }
    return tiles;
  }

  Future<void> _openSurvey() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const WelcomeSurveyPage(
          role: 'patient',
          updateExisting: true,
        ),
      ),
    );
    if (updated == true && mounted) {
      await _loadProfile();
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final result = await showDialog<(String, String, String)?>(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );

    if (result == null || !mounted) return;

    final (cur, n, c) = result;

    if (cur.isEmpty || n.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in current and new password')),
      );
      return;
    }
    if (n != c) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match')),
      );
      return;
    }
    if (n.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password should be at least 6 characters'),
        ),
      );
      return;
    }

    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: cur,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(n);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = e.message ?? 'Could not change password';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = 'Current password is incorrect';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final t = AppLanguage.instance.t;

    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: Text(t('profile')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : user == null
              ? Center(child: Text(t('notSignedIn')))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t('displayName'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppKeyboardField(
                        controller: _nameController,
                        enableTidyUp: false,
                        hideTidyUp: true,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          hintText: t('displayNameHint'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _savingName ? null : _saveDisplayName,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          _savingName ? t('saving') : t('saveDisplayName'),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        AppLanguage.instance.t('language'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLanguage.instance.t('languageHelp'),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final lang in AppLang.values)
                            ChoiceChip(
                              label: Text(lang.nativeName),
                              selected:
                                  AppLanguage.instance.lang == lang,
                              selectedColor: Colors.blueAccent,
                              labelStyle: TextStyle(
                                color: AppLanguage.instance.lang == lang
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                              onSelected: (_) =>
                                  AppLanguage.instance.setLang(lang),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        AppLanguage.instance.t('aLittleAboutYou'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _survey.isEmpty
                            ? t('surveyEmptyHelp')
                            : t('surveyFilledHelp'),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blueGrey.shade700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_survey.isNotEmpty) ..._surveyTiles(),
                      ElevatedButton(
                        onPressed: _openSurvey,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          _survey.isEmpty
                              ? t('addQuestionnaire')
                              : t('updateQuestionnaire'),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        t('account'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoTile(
                        label: t('email'),
                        value: user.email ?? '—',
                      ),
                      const SizedBox(height: 8),
                      _InfoTile(
                        label: t('password'),
                        value: '••••••••',
                        subtitle: t('passwordHidden'),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: _showChangePasswordDialog,
                        child: Text(t('changePassword')),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'User ID: ${user.uid}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
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

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppKeyboardField(
              controller: _current,
              enableTidyUp: false,
              hideTidyUp: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current password',
              ),
            ),
            AppKeyboardField(
              controller: _next,
              enableTidyUp: false,
              hideTidyUp: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password',
              ),
            ),
            AppKeyboardField(
              controller: _confirm,
              enableTidyUp: false,
              hideTidyUp: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(
              context,
              (_current.text, _next.text, _confirm.text),
            );
          },
          child: const Text('Update'),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[800],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 16),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ],
      ),
    );
  }
}
