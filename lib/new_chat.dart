import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:swiftspeak/app_keyboard.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/home_page.dart';
import 'package:swiftspeak/ai_chat_service.dart';
import 'package:swiftspeak/chat_repository.dart';
import 'package:swiftspeak/typing_prediction.dart';

class NewChat extends StatefulWidget {
  const NewChat({super.key, this.chatId});

  /// If null -> open most recent chat (do NOT create unless none exist)
  final String? chatId;

  @override
  State<NewChat> createState() => _NewChatState();
}

class _NewChatState extends State<NewChat> {
  final TextEditingController _controller = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();

  final ChatRepository _repo = ChatRepository();
  final AiChatService _ai = AiChatService();

  String? _chatId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _flutterTts.setLanguage(AppLanguage.instance.ttsLanguage);
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setPitch(1.0);

    _chatId = widget.chatId;

    // If no chatId passed, OPEN last chat. Only create if none exists.
    if (_chatId == null) {
      _openMostRecentOrCreate();
    }
  }

  Future<void> _openMostRecentOrCreate() async {
    setState(() => _isLoading = true);
    try {
      final lastId = await _repo.getMostRecentChatId();
      if (lastId != null) {
        setState(() => _chatId = lastId);
      } else {
        // Only create if user has zero chats
        final id = await _repo.createNewChat();
        setState(() => _chatId = id);
      }
    } catch (e) {
      _showSnack(AppLanguage.instance.t('failedToOpenChat', {'error': '$e'}));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openChat(String chatId) async {
    Navigator.pop(context); // close drawer
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => NewChat(chatId: chatId)),
    );
  }

  Future<void> _createNewAndOpen() async {
    setState(() => _isLoading = true);
    try {
      final id = await _repo.createNewChat();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => NewChat(chatId: id)),
      );
    } catch (e) {
      _showSnack(AppLanguage.instance.t('failedToCreateChat', {'error': '$e'}));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendUserMessage() async {
    final chatId = _chatId;
    if (chatId == null) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;
    TypingPredictionStore.instance.learnFromCommitted(
      text,
      surface: 'chatbot',
    );

    setState(() => _isLoading = true);
    _controller.clear();

    try {
      // Save user message
      await _repo.addMessage(chatId: chatId, text: text, isUser: true);

      // Load recent messages for context
      final recent = await _fetchRecentMessages(chatId, limit: 24);

      // ✅ AI reply (persona is enforced inside AiChatService)
      final reply = await _ai.generateAssistantReply(chatMessages: recent);
      await _repo.addMessage(chatId: chatId, text: reply, isUser: false);
      TypingPredictionStore.instance.setConversationHint(reply);

      // ---- Title rule: date + summary, generated after first user message ----
      final meta = await _repo.getChatMeta(chatId);
      final alreadyGenerated = (meta?['titleGenerated'] ?? false) == true;
      final dateStr = (meta?['dateStr'] ?? _formatDate(DateTime.now())).toString();

      if (!alreadyGenerated) {
        final after = await _fetchRecentMessages(chatId, limit: 24);
        final summary = await _ai.generateChatTitle(chatMessages: after);

        final finalTitle =
        summary.isEmpty
            ? '$dateStr — ${AppLanguage.instance.t('newChatTitle')}'
            : '$dateStr — $summary';

        await _repo.setTitle(
          chatId: chatId,
          title: finalTitle,
          titleGenerated: true,
        );
      }
    } catch (e) {
      _showSnack(AppLanguage.instance.t('sendFailed', {'error': '$e'}));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateAiRecommendation() async {
    final chatId = _chatId;
    if (chatId == null) return;

    setState(() => _isLoading = true);
    try {
      final recent = await _fetchRecentMessages(chatId, limit: 24);

      // ✅ Recommendation uses same persona inside AiChatService
      final rec = await _ai.generateRecommendation(chatMessages: recent);

      await _repo.addMessage(
        chatId: chatId,
        text: "${AppLanguage.instance.t('aiRecPrefix')}\n$rec",
        isUser: false,
      );
    } catch (e) {
      _showSnack(AppLanguage.instance.t('recFailed', {'error': '$e'}));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _speakLastAppMessage() async {
    final chatId = _chatId;
    if (chatId == null) return;

    try {
      final snap = await _repo
          .messagesCol(chatId)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final isUser = (data['isUser'] ?? false) == true;
        if (!isUser) {
          final text = (data['text'] ?? '').toString();
          if (text.trim().isEmpty) continue;
          await _flutterTts.setLanguage(AppLanguage.instance.ttsLanguage);
          await _flutterTts.stop();
          await _flutterTts.speak(text);
          break;
        }
      }
    } catch (e) {
      _showSnack(AppLanguage.instance.t('ttsFailed', {'error': '$e'}));
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRecentMessages(
      String chatId, {
        int limit = 24,
      }) async {
    final snap = await _repo.messagesCol(chatId)
        .orderBy('createdAt', descending: false)
        .limitToLast(limit)
        .get();

    return snap.docs.map((d) {
      final m = d.data();
      return {
        "text": (m["text"] ?? "").toString(),
        "isUser": (m["isUser"] ?? false) == true,
      };
    }).toList();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Widget _buildChatBubble({required String text, required bool isUser}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isUser ? Colors.blueAccent.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppLangBuilder(
      builder: (context, t) {
    final chatId = _chatId;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FC),

      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.blueAccent),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    t('aiChatbot'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(t('newChat')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 42),
                    ),
                    onPressed: _isLoading ? null : _createNewAndOpen,
                  ),
                ],
              ),
            ),

            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _repo.chatsStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("Error: ${snapshot.error}"));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return Center(child: Text(t('noChatsYet')));
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final d = docs[index];
                      final data = d.data();
                      final title = (data['title'] ?? 'Chat').toString();
                      final selected = d.id == chatId;

                      return ListTile(
                        leading: const Icon(Icons.chat_bubble_outline, color: Colors.blueAccent),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: selected,
                        onTap: () => _openChat(d.id),
                      );
                    },
                  );
                },
              ),
            ),

            const Divider(),

            ListTile(
              leading: const Icon(Icons.home),
              title: Text(t('backToHome')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HomePage()),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),

      appBar: AppBar(
        title: Text(t('aiChatbot')),
        backgroundColor: Colors.blueAccent,
      ),

      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.psychology, color: Colors.white),
                label: Text(
                  t('aiRecommendation'),
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: (_isLoading || chatId == null) ? null : _generateAiRecommendation,
              ),
            ),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: CircularProgressIndicator(),
              ),

            Expanded(
              child: chatId == null
                  ? Center(child: Text(t('openingLatestChat')))
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _repo.messagesStream(chatId),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("Error: ${snapshot.error}"));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final text = (data['text'] ?? '').toString();
                      final isUser = (data['isUser'] ?? false) == true;
                      return _buildChatBubble(text: text, isUser: isUser);
                    },
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: AppKeyboardField(
                      controller: _controller,
                      enableTidyUp: true,
                      enablePredictions: true,
                      predictionSurface: 'chatbot',
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: t('typeMessage'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blueAccent, size: 30),
                    onPressed: (_isLoading || chatId == null) ? null : _sendUserMessage,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ElevatedButton(
                onPressed: chatId == null ? null : _speakLastAppMessage,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                child: Text(t('textToSpeech'), style: const TextStyle(fontSize: 18)),
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