import 'package:flutter/material.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/mood_check2.dart';
import 'mood_check4.dart';

class MoodCheck extends StatefulWidget {
  const MoodCheck({super.key});

  @override
  State<MoodCheck> createState() => _MoodCheckState();
}

class _MoodCheckState extends State<MoodCheck> {
  void _goToSliders(String mood) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => MoodCheck2(moodToday: mood)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppLangBuilder(
      builder: (context, t) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blueAccent,
            title: Text(t('moodCheck')),
          ),
          body: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(t('howAreYouToday'), style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 10),
              ElevatedButton(
                child: Text("😊 ${t('moodGood')}", style: const TextStyle(fontSize: 30)),
                onPressed: () => _goToSliders("Good"),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                child: Text("🙂 ${t('moodOkay')}", style: const TextStyle(fontSize: 30)),
                onPressed: () => _goToSliders("Okay"),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                child: Text("😐 ${t('moodNeutral')}", style: const TextStyle(fontSize: 30)),
                onPressed: () => _goToSliders("Neutral"),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                child: Text("🙁 ${t('moodNotGood')}", style: const TextStyle(fontSize: 30)),
                onPressed: () => _goToSliders("Not Good"),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                child: Text("😢 ${t('moodDifficult')}", style: const TextStyle(fontSize: 30)),
                onPressed: () => _goToSliders("Difficult"),
              ),
              const SizedBox(height: 50),
              ElevatedButton(
                child: Text(t('moodHistory'), style: const TextStyle(fontSize: 26)),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const MoodCheck4()),
                  );
                },
              ),
            ]),
          ),
        );
      },
    );
  }
}
