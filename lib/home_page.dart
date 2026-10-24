import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:swiftspeak/app_keyboard.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/body_check.dart';
import 'package:swiftspeak/communicate.dart';
import 'package:swiftspeak/community_page.dart';
import 'package:swiftspeak/login.dart';
import 'package:swiftspeak/mood_check.dart';
import 'package:swiftspeak/new_chat.dart';
import 'package:swiftspeak/patient_profile_page.dart';
import 'package:swiftspeak/typing_prediction.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    CommunityStore.instance.start();
    TypingPredictionStore.instance.start();
    AppKeyboardController.instance.hide();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        final t = AppLanguage.instance.t;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blueAccent,
            title: Text(t('welcome')),
            actions: [
              IconButton(
                tooltip: t('profile'),
                icon: const Icon(Icons.person_outline),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PatientProfilePage(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                children: [
                  Text(
                    t('patientTools'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ToolTile(
                            title: t('bodyCheck'),
                            hint: t('bodyCheckHint'),
                            icon: const _ToolIcon(
                              asset: 'assets/icons/body_check.png',
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const BodyCheck(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ToolTile(
                            title: t('communication'),
                            hint: t('communicationHint'),
                            icon: const _ToolIcon(
                              asset: 'assets/icons/communication.png',
                              topPadding: 12,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const Communicate(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ToolTile(
                            title: t('moodCheck'),
                            hint: t('moodCheckHint'),
                            icon: const _ToolIcon(
                              asset: 'assets/icons/mood_check.png',
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const MoodCheck(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ToolTile(
                            title: t('aiChatbot'),
                            hint: t('aiChatbotHint'),
                            icon: const _ToolIcon(
                              asset: 'assets/icons/chatbot.png',
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const NewChat(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Spacer(),
                      Expanded(
                        flex: 2,
                        child: _ToolTile(
                          title: t('communityPage'),
                          hint: t('communityHint'),
                          icon: const _ToolIcon(
                            asset: 'assets/icons/community.png',
                            width: 88,
                            height: 66,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CommunityPage(),
                              ),
                            );
                          },
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
                    child: ElevatedButton(
                      child: Text(
                        t('logOut'),
                        style: const TextStyle(fontSize: 22),
                      ),
                      onPressed: () async {
                        await CommunityStore.instance.reset();
                        await TypingPredictionStore.instance.reset();
                        await FirebaseAuth.instance.signOut();

                        if (!mounted) return;

                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const Login(),
                          ),
                          (route) => false,
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

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.title,
    required this.hint,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String hint;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(width: 1, color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
            child: Column(
              children: [
                icon,
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({
    required this.asset,
    this.width = 80,
    this.height = 80,
    this.topPadding = 0,
  });

  final String asset;
  final double width;
  final double height;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: FittedBox(
          fit: BoxFit.contain,
          child: Image(image: AssetImage(asset)),
        ),
      ),
    );
  }
}
