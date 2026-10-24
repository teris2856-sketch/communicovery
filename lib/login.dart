import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:swiftspeak/app_keyboard.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/signup.dart';
import 'package:swiftspeak/welcome_survey_page.dart';
import 'home_page.dart';
import 'staff_home_page.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> loginUser() async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final uid = _auth.currentUser!.uid;
      final doc = await _firestore.collection('users').doc(uid).get();
      final role = doc.data()?['role'] as String?;
      final needsSurvey = doc.data()?['surveyCompleted'] == false;
      await AppLanguage.instance.applyFromUserDoc(doc.data());

      if (!mounted) return;

      if (needsSurvey) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WelcomeSurveyPage(role: role ?? 'patient'),
          ),
        );
        return;
      }

      if (role == 'staff') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StaffHomePage()),
        );
      } else {
        if (role != 'patient' && doc.exists == false) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No profile found. Complete sign up to choose your role.',
              ),
            ),
          );
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed: ${e.toString()}")),
      );
    }
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
        title: Text(t('login')),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(t('login'), style: const TextStyle(fontSize: 50)),

            Padding(
              padding: const EdgeInsets.all(10),
              child: AppKeyboardField(
                controller: emailController,
                enableTidyUp: false,
                hideTidyUp: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: t('email'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(10),
              child: AppKeyboardField(
                controller: passwordController,
                enableTidyUp: false,
                hideTidyUp: true,
                obscureText: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: t('password'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: loginUser,
              child: Text(t('login'), style: const TextStyle(fontSize: 18)),
            ),

            const SizedBox(height: 10),

            Text(t('signUpIfNeeded')),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const Signup()),
                );
              },
              child: Text(t('signUp'), style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}