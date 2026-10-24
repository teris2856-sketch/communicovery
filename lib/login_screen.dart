import 'package:flutter/material.dart';
import 'package:swiftspeak/app_keyboard.dart';
import 'package:swiftspeak/app_language.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: Text(AppLanguage.instance.t('login')),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
                AppLanguage.instance.t('login'),
        style: const TextStyle(fontSize: 35),
            ),
            AppKeyboardField(
              enableTidyUp: false,
              hideTidyUp: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Name/Email/Phone Number"
              ),
            ),
            AppKeyboardField(
              enableTidyUp: false,
              hideTidyUp: true,
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Password"
              ),
            ),
            ElevatedButton(
              child: Text(
                "Login",
                style: TextStyle(
                    fontSize: 20
                ),
              ),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => Placeholder()));
              },
            ),
            TextButton(
              child: Text(
                "Forgot Password?",
                style: TextStyle(
                    fontSize: 17
                ),
              ),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => Placeholder()));
              },
            )
              ],
            )
      ),
        );
  }
}
