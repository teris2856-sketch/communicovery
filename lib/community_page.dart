import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swiftspeak/ai_chat_service.dart';
import 'package:swiftspeak/app_keyboard.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/typing_prediction.dart';

enum CommunityFilter {
  forYou,
  all,
  latest,
  gettingStarted,
  unanswered,
  faqs,
  yourQuestions,
  saved,
}

extension CommunityFilterLabel on CommunityFilter {
  String get label {
    final t = AppLanguage.instance.t;
    switch (this) {
      case CommunityFilter.forYou:
        return t('forYou');
      case CommunityFilter.all:
        return t('all');
      case CommunityFilter.latest:
        return t('latest');
      case CommunityFilter.gettingStarted:
        return t('gettingStarted');
      case CommunityFilter.unanswered:
        return t('unanswered');
      case CommunityFilter.faqs:
        return t('faqs');
      case CommunityFilter.yourQuestions:
        return t('yourQuestions');
      case CommunityFilter.saved:
        return t('saved');
    }
  }

  String get feedTitle {
    final t = AppLanguage.instance.t;
    switch (this) {
      case CommunityFilter.forYou:
        return t('feedForYou');
      case CommunityFilter.all:
        return t('feedAll');
      case CommunityFilter.latest:
        return t('feedLatest');
      case CommunityFilter.gettingStarted:
        return t('feedGettingStarted');
      case CommunityFilter.unanswered:
        return t('feedUnanswered');
      case CommunityFilter.faqs:
        return t('feedFaqs');
      case CommunityFilter.yourQuestions:
        return t('feedYourQuestions');
      case CommunityFilter.saved:
        return t('feedSaved');
    }
  }

  String get emptyMessage {
    final t = AppLanguage.instance.t;
    switch (this) {
      case CommunityFilter.yourQuestions:
        return t('emptyYourQuestions');
      case CommunityFilter.saved:
        return t('emptySaved');
      default:
        return t('emptyPosts');
    }
  }
}

enum CommunityRole { recoveryMember, caregiver }

extension CommunityRoleLabel on CommunityRole {
  String get label {
    switch (this) {
      case CommunityRole.recoveryMember:
        return AppLanguage.instance.t('recoveryMember');
      case CommunityRole.caregiver:
        return AppLanguage.instance.t('caregiver');
    }
  }
}

const communityTagOptions = <String>[
  'Fatigue',
  'Symptoms',
  'Getting Started',
  'FAQs',
  'Medication',
  'Caregiver',
  'Appointments',
];

String communityHandle(String name) {
  return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

List<String> parseMentionHandles(String text) {
  return RegExp(r'@[A-Za-z0-9_]+')
      .allMatches(text)
      .map((match) => match.group(0)!.substring(1).toLowerCase())
      .toSet()
      .toList();
}

TextSpan mentionTextSpan(String text, [TextStyle? style]) {
  final matches = RegExp(r'@[A-Za-z0-9_]+').allMatches(text).toList();
  if (matches.isEmpty) {
    return TextSpan(text: text, style: style);
  }
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start), style: style));
    }
    spans.add(
      TextSpan(
        text: match.group(0),
        style: (style ?? const TextStyle()).copyWith(
          color: Colors.blueAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: style));
  }
  return TextSpan(style: style, children: spans);
}

class CommunityMember {
  const CommunityMember({
    required this.uid,
    required this.displayName,
    required this.handle,
  });

  final String uid;
  final String displayName;
  final String handle;
}

class CommunityNotification {
  const CommunityNotification({
    required this.id,
    required this.type,
    required this.postId,
    required this.postTitle,
    required this.actorName,
    required this.actorId,
    required this.createdAt,
    this.preview = '',
    this.read = false,
  });

  final String id;
  final String type;
  final String postId;
  final String postTitle;
  final String actorName;
  final String actorId;
  final String preview;
  final bool read;
  final DateTime createdAt;

  String get title {
    switch (type) {
      case 'mention':
        return '$actorName mentioned you';
      case 'comment_reply':
        return '$actorName replied to a comment';
      case 'helpful':
        return '$actorName found your post helpful';
      case 'saved_reply':
        return '$actorName replied to a saved post';
      default:
        return '$actorName replied to your post';
    }
  }

  factory CommunityNotification.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final json = doc.data();
    return CommunityNotification(
      id: doc.id,
      type: json['type'] as String? ?? 'reply',
      postId: json['postId'] as String? ?? '',
      postTitle: json['postTitle'] as String? ?? 'a conversation',
      actorName: json['actorName'] as String? ?? 'Someone',
      actorId: json['actorId'] as String? ?? '',
      preview: json['preview'] as String? ?? '',
      read: json['read'] == true,
      createdAt: _communityDate(json['createdAt']),
    );
  }
}

DateTime _communityDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}

class CommunityReply {
  const CommunityReply({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.authorId = '',
  });

  final String id;
  final String author;
  final String authorId;
  final String text;
  final DateTime createdAt;

  factory CommunityReply.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final json = doc.data();
    return CommunityReply(
      id: doc.id,
      author: json['author'] as String? ?? 'Member',
      authorId: json['authorId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdAt: _communityDate(json['createdAt']),
    );
  }
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.author,
    required this.authorId,
    required this.role,
    required this.title,
    required this.text,
    required this.createdAt,
    this.stage,
    this.tags = const [],
    this.replies = const [],
    this.helpfulBy = const [],
    this.replyCount = 0,
  });

  final String id;
  final String author;
  final String authorId;
  final CommunityRole role;
  final String? stage;
  final String title;
  final String text;
  final DateTime createdAt;
  final List<String> tags;
  final List<CommunityReply> replies;
  final List<String> helpfulBy;
  final int replyCount;

  String get roleLine {
    if (stage == null || stage!.trim().isEmpty) return role.label;
    return '${role.label} - $stage';
  }

  int get helpfulCount => helpfulBy.length;

  int get displayedReplyCount =>
      replies.isNotEmpty ? replies.length : replyCount;

  bool isHelpfulFor(String userId) => helpfulBy.contains(userId);

  CommunityPost copyWith({
    List<CommunityReply>? replies,
    List<String>? helpfulBy,
    int? replyCount,
  }) {
    return CommunityPost(
      id: id,
      author: author,
      authorId: authorId,
      role: role,
      stage: stage,
      title: title,
      text: text,
      createdAt: createdAt,
      tags: tags,
      replies: replies ?? this.replies,
      helpfulBy: helpfulBy ?? this.helpfulBy,
      replyCount: replyCount ?? this.replyCount,
    );
  }

  factory CommunityPost.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return CommunityPost.fromData(doc.id, doc.data());
  }

  factory CommunityPost.fromData(String id, Map<String, dynamic> json) {
    final text = json['text'] as String? ?? '';
    final tags = ((json['tags'] as List?) ?? [])
        .map((item) => item.toString())
        .toList();
    return CommunityPost(
      id: id,
      author: json['author'] as String? ?? 'Member',
      authorId: json['authorId'] as String? ?? '',
      role: CommunityRole.values.firstWhere(
        (role) => role.name == json['role'],
        orElse: () => CommunityRole.recoveryMember,
      ),
      stage: json['stage'] as String?,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : _titleFromText(text),
      text: text,
      createdAt: _communityDate(json['createdAt']),
      tags: tags,
      helpfulBy: ((json['helpfulBy'] as List?) ?? [])
          .map((item) => item.toString())
          .toList(),
      replyCount: (json['replyCount'] as num?)?.toInt() ?? 0,
    );
  }

  static String _titleFromText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'Community question';
    final firstLine = trimmed.split('\n').first.trim();
    if (firstLine.length <= 72) return firstLine;
    return '${firstLine.substring(0, 72).trim()}â€¦';
  }
}

class CommunityStore extends ChangeNotifier {
  CommunityStore._();
  static final CommunityStore instance = CommunityStore._();

  static const _savedKey = 'community_saved_ids';
  static const _reportedKey = 'community_reported_ids';
  static const _blockedKey = 'community_blocked_author_ids';
  static const _rulesKey = 'community_accepted_rules';

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _postsCol =>
      _db.collection('community_posts');

  List<CommunityPost> posts = [];
  List<CommunityNotification> notifications = [];
  List<CommunityMember> members = [];
  Set<String> savedIds = {};
  Set<String> reportedIds = {};
  Set<String> blockedAuthorIds = {};
  bool acceptedRules = false;
  bool loading = true;
  String? loadError;
  String? _uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _postsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _profilesSub;
  StreamSubscription<User?>? _authSub;

  int get unreadCount =>
      notifications.where((item) => !item.read).length;

  List<CommunityMember> get mentionable {
    final byHandle = <String, CommunityMember>{};
    for (final member in members) {
      if (member.handle.isEmpty || member.uid == _uid) continue;
      byHandle[member.handle] = member;
    }
    for (final post in posts) {
      final handle = communityHandle(post.author);
      if (handle.isEmpty || post.authorId.isEmpty || post.authorId == _uid) {
        continue;
      }
      byHandle.putIfAbsent(
        handle,
        () => CommunityMember(
          uid: post.authorId,
          displayName: post.author,
          handle: handle,
        ),
      );
    }
    final list = byHandle.values.toList()
      ..sort((a, b) => a.handle.compareTo(b.handle));
    return list;
  }

  Future<void> start() async {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      _bindToUser(user);
    });
    await _bindToUser(FirebaseAuth.instance.currentUser);
  }

  Future<void> reset() async {
    await _postsSub?.cancel();
    await _notifsSub?.cancel();
    await _profilesSub?.cancel();
    _postsSub = null;
    _notifsSub = null;
    _profilesSub = null;
    _uid = null;
    posts = [];
    notifications = [];
    members = [];
    savedIds = {};
    reportedIds = {};
    blockedAuthorIds = {};
    acceptedRules = false;
    loading = true;
    loadError = null;
    notifyListeners();
  }

  Future<void> _bindToUser(User? user) async {
    final nextUid = user?.uid;
    if (nextUid == _uid && _postsSub != null && loadError == null) {
      return;
    }
    await _postsSub?.cancel();
    await _notifsSub?.cancel();
    await _profilesSub?.cancel();
    _postsSub = null;
    _notifsSub = null;
    _profilesSub = null;
    _uid = nextUid;
    posts = [];
    notifications = [];
    members = [];
    loading = true;
    loadError = null;
    notifyListeners();

    if (user == null) {
      savedIds = {};
      reportedIds = {};
      blockedAuthorIds = {};
      acceptedRules = false;
      loading = false;
      loadError = 'Please sign in to view the community.';
      notifyListeners();
      return;
    }

    await _loadPrefs(user.uid);
    try {
      await user.getIdToken();
      await _syncMyProfile(user);
      _profilesSub = _db.collection('community_profiles').snapshots().listen(
        (snap) {
          members = snap.docs.map((doc) {
            final data = doc.data();
            final name = (data['displayName'] as String?)?.trim() ?? 'Member';
            return CommunityMember(
              uid: doc.id,
              displayName: name,
              handle: (data['handle'] as String?)?.trim().isNotEmpty == true
                  ? (data['handle'] as String).trim().toLowerCase()
                  : communityHandle(name),
            );
          }).toList();
          notifyListeners();
        },
        onError: (_) {},
      );
      _notifsSub = _db
          .collection('community_notifications')
          .doc(user.uid)
          .collection('items')
          .orderBy('createdAt', descending: true)
          .limit(80)
          .snapshots()
          .listen(
        (snap) {
          notifications =
              snap.docs.map(CommunityNotification.fromDoc).toList();
          notifyListeners();
        },
        onError: (_) {},
      );
      _postsSub = _postsCol
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen(
        (snap) {
          posts = snap.docs.map(CommunityPost.fromDoc).toList();
          loading = false;
          loadError = null;
          notifyListeners();
        },
        onError: (Object error) {
          loading = false;
          loadError = error.toString();
          notifyListeners();
        },
      );
    } catch (error) {
      loading = false;
      loadError = error.toString();
      notifyListeners();
    }
  }

  Future<void> retry() => start();

  Future<void> _loadPrefs(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    savedIds = (prefs.getStringList('${_savedKey}_$uid') ??
            prefs.getStringList(_savedKey) ??
            [])
        .toSet();
    reportedIds = (prefs.getStringList('${_reportedKey}_$uid') ??
            prefs.getStringList(_reportedKey) ??
            [])
        .toSet();
    blockedAuthorIds = (prefs.getStringList('${_blockedKey}_$uid') ??
            prefs.getStringList(_blockedKey) ??
            [])
        .toSet();
    acceptedRules = prefs.getBool('${_rulesKey}_$uid') ??
        prefs.getBool(_rulesKey) ??
        false;
  }

  Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _uid == null ? _savedKey : '${_savedKey}_$_uid';
    await prefs.setStringList(key, savedIds.toList());
    notifyListeners();
  }

  Future<String> resolveAuthorName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Member';
    final authName = user.displayName?.trim();
    if (authName != null && authName.isNotEmpty) return authName;
    final doc = await _db.collection('users').doc(user.uid).get();
    final name = (doc.data()?['displayName'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }
    return 'Member';
  }

  Future<void> addPost(CommunityPost post) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Please sign in to post.');
    }
    final ref = await _postsCol.add({
      'author': post.author,
      'authorId': user.uid,
      'role': post.role.name,
      'stage': post.stage,
      'title': post.title,
      'text': post.text,
      'createdAt': FieldValue.serverTimestamp(),
      'tags': post.tags,
      'helpfulBy': <String>[],
      'replyCount': 0,
    });
    await _notifyMentions(
      text: '${post.title} ${post.text}',
      postId: ref.id,
      postTitle: post.title,
      actorName: post.author,
      actorId: user.uid,
      alreadyNotified: {user.uid},
    );
  }

  Future<void> addReply(String postId, CommunityReply reply) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Please sign in to reply.');
    }
    final postRef = _postsCol.doc(postId);
    await postRef.collection('replies').add({
      'author': reply.author,
      'authorId': user.uid,
      'text': reply.text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await postRef.update({'replyCount': FieldValue.increment(1)});

    final postSnap = await postRef.get();
    final postData = postSnap.data() ?? {};
    final postTitle = (postData['title'] as String?)?.trim().isNotEmpty == true
        ? postData['title'] as String
        : 'a conversation';
    final postAuthorId = postData['authorId'] as String? ?? '';
    final notified = <String>{user.uid};

    if (postAuthorId.isNotEmpty && postAuthorId != user.uid) {
      await _notify(
        recipientId: postAuthorId,
        type: 'reply',
        postId: postId,
        postTitle: postTitle,
        actorName: reply.author,
        actorId: user.uid,
        preview: reply.text,
      );
      notified.add(postAuthorId);
    }

    final repliesSnap = await postRef.collection('replies').get();
    for (final doc in repliesSnap.docs) {
      final commenterId = doc.data()['authorId'] as String? ?? '';
      if (commenterId.isEmpty || notified.contains(commenterId)) continue;
      await _notify(
        recipientId: commenterId,
        type: 'comment_reply',
        postId: postId,
        postTitle: postTitle,
        actorName: reply.author,
        actorId: user.uid,
        preview: reply.text,
      );
      notified.add(commenterId);
    }

    final savers = await _db
        .collection('community_saves')
        .doc(postId)
        .collection('users')
        .get();
    for (final saver in savers.docs) {
      if (notified.contains(saver.id)) continue;
      await _notify(
        recipientId: saver.id,
        type: 'saved_reply',
        postId: postId,
        postTitle: postTitle,
        actorName: reply.author,
        actorId: user.uid,
        preview: reply.text,
      );
      notified.add(saver.id);
    }

    await _notifyMentions(
      text: reply.text,
      postId: postId,
      postTitle: postTitle,
      actorName: reply.author,
      actorId: user.uid,
      alreadyNotified: notified,
    );
  }

  Stream<List<CommunityReply>> repliesStream(String postId) {
    return _postsCol
        .doc(postId)
        .collection('replies')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map(CommunityReply.fromDoc).toList());
  }

  Future<void> toggleHelpful(String postId, String userId) async {
    if (userId.isEmpty || userId == 'local') {
      throw StateError('Please sign in to mark a post helpful.');
    }
    final ref = _postsCol.doc(postId);
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final current = List<String>.from(data['helpfulBy'] ?? const []);
    final adding = !current.contains(userId);
    await ref.update({
      'helpfulBy': adding
          ? FieldValue.arrayUnion([userId])
          : FieldValue.arrayRemove([userId]),
    });
    if (adding) {
      final authorId = data['authorId'] as String? ?? '';
      final title = (data['title'] as String?)?.trim().isNotEmpty == true
          ? data['title'] as String
          : 'a conversation';
      await _notify(
        recipientId: authorId,
        type: 'helpful',
        postId: postId,
        postTitle: title,
        actorName: await resolveAuthorName(),
        actorId: userId,
      );
    }
  }

  Future<void> toggleSaved(String postId) async {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (savedIds.contains(postId)) {
      savedIds.remove(postId);
      if (uid != null) {
        try {
          await _db
              .collection('community_saves')
              .doc(postId)
              .collection('users')
              .doc(uid)
              .delete();
        } catch (_) {}
      }
    } else {
      savedIds.add(postId);
      if (uid != null) {
        try {
          await _db
              .collection('community_saves')
              .doc(postId)
              .collection('users')
              .doc(uid)
              .set({'savedAt': FieldValue.serverTimestamp()});
        } catch (_) {}
      }
    }
    await _saveBookmarks();
  }

  Future<void> _syncMyProfile(User user) async {
    try {
      final name = await resolveAuthorName();
      final handle = communityHandle(name);
      if (handle.isEmpty) return;
      await _db.collection('community_profiles').doc(user.uid).set(
        {
          'displayName': name,
          'handle': handle,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> _notifyMentions({
    required String text,
    required String postId,
    required String postTitle,
    required String actorName,
    required String actorId,
    required Set<String> alreadyNotified,
  }) async {
    final handles = parseMentionHandles(text);
    if (handles.isEmpty) return;
    final targets = mentionable.where((member) => handles.contains(member.handle));
    for (final member in targets) {
      if (alreadyNotified.contains(member.uid)) continue;
      await _notify(
        recipientId: member.uid,
        type: 'mention',
        postId: postId,
        postTitle: postTitle,
        actorName: actorName,
        actorId: actorId,
        preview: text,
      );
      alreadyNotified.add(member.uid);
    }
  }

  Future<void> _notify({
    required String recipientId,
    required String type,
    required String postId,
    required String postTitle,
    required String actorName,
    required String actorId,
    String preview = '',
  }) async {
    if (recipientId.isEmpty || recipientId == actorId) return;
    try {
      await _db
          .collection('community_notifications')
          .doc(recipientId)
          .collection('items')
          .add({
        'type': type,
        'postId': postId,
        'postTitle': postTitle,
        'actorName': actorName,
        'actorId': actorId,
        'preview': preview,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> markNotificationRead(String notificationId) async {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('community_notifications')
        .doc(uid)
        .collection('items')
        .doc(notificationId)
        .update({'read': true});
  }

  Future<void> markAllNotificationsRead() async {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final unread = notifications.where((item) => !item.read);
    for (final item in unread) {
      await markNotificationRead(item.id);
    }
  }

  Future<void> _saveModeration() async {
    final prefs = await SharedPreferences.getInstance();
    final suffix = _uid == null ? '' : '_$_uid';
    await prefs.setStringList('$_reportedKey$suffix', reportedIds.toList());
    await prefs.setStringList('$_blockedKey$suffix', blockedAuthorIds.toList());
    notifyListeners();
  }

  Future<void> reportPost(String postId) async {
    reportedIds.add(postId);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _db.collection('community_reports').add({
        'postId': postId,
        'reporterId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await _saveModeration();
  }

  Future<void> blockAuthor(String authorId) async {
    if (authorId.isEmpty) return;
    blockedAuthorIds.add(authorId);
    await _saveModeration();
  }

  Future<void> acceptRules() async {
    acceptedRules = true;
    final prefs = await SharedPreferences.getInstance();
    final key = _uid == null ? _rulesKey : '${_rulesKey}_$_uid';
    await prefs.setBool(key, true);
    notifyListeners();
  }
}

Future<bool> ensureCommunityRulesAccepted(BuildContext context) async {
  if (CommunityStore.instance.acceptedRules) return true;
  final accepted = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => const _CommunityRulesPage(requireAccept: true),
    ),
  );
  return accepted == true;
}

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  CommunityFilter _filter = CommunityFilter.forYou;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    CommunityStore.instance.start();
  }

  String get _userId {
    return FirebaseAuth.instance.currentUser?.uid ?? 'local';
  }

  List<CommunityPost> get _visiblePosts {
    final needle = _query.trim().toLowerCase();
    final now = DateTime.now();
    final store = CommunityStore.instance;
    var posts = store.posts.where((post) {
      final isOwn = post.authorId == _userId;
      if (!isOwn && store.blockedAuthorIds.contains(post.authorId)) {
        return false;
      }
      if (!isOwn && store.reportedIds.contains(post.id)) {
        return false;
      }
      final searchOk = needle.isEmpty ||
          post.title.toLowerCase().contains(needle) ||
          post.text.toLowerCase().contains(needle) ||
          post.author.toLowerCase().contains(needle) ||
          post.tags.any((tag) => tag.toLowerCase().contains(needle));
      if (!searchOk) return false;
      switch (_filter) {
        case CommunityFilter.forYou:
        case CommunityFilter.all:
        case CommunityFilter.latest:
          return true;
        case CommunityFilter.gettingStarted:
          return post.tags.contains('Getting Started');
        case CommunityFilter.unanswered:
          return post.displayedReplyCount == 0;
        case CommunityFilter.faqs:
          return post.tags.contains('FAQs');
        case CommunityFilter.yourQuestions:
          return post.authorId == _userId;
        case CommunityFilter.saved:
          return CommunityStore.instance.savedIds.contains(post.id);
      }
    }).toList();

    switch (_filter) {
      case CommunityFilter.latest:
        posts = posts
            .where((post) => now.difference(post.createdAt).inDays <= 14)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case CommunityFilter.forYou:
        posts.sort((a, b) {
          final helpful = b.helpfulCount.compareTo(a.helpfulCount);
          if (helpful != 0) return helpful;
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
      case CommunityFilter.all:
      case CommunityFilter.gettingStarted:
      case CommunityFilter.unanswered:
      case CommunityFilter.faqs:
      case CommunityFilter.yourQuestions:
      case CommunityFilter.saved:
        posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
    return posts;
  }

  Future<void> _askCommunity() async {
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to post.')),
      );
      return;
    }
    final allowed = await ensureCommunityRulesAccepted(context);
    if (!allowed || !mounted) return;
    final name = await CommunityStore.instance.resolveAuthorName();
    if (!mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _AskCommunityPage(authorName: name),
      ),
    );
  }

  void _openRules({bool requireAccept = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _CommunityRulesPage(requireAccept: requireAccept),
      ),
    );
  }

  Future<void> _openPost(CommunityPost post) async {
    final name = await CommunityStore.instance.resolveAuthorName();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _CommunityPostPage(
          postId: post.id,
          authorName: name,
        ),
      ),
    );
  }

  Future<void> _toggleHelpful(CommunityPost post) async {
    try {
      await CommunityStore.instance.toggleHelpful(post.id, _userId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update helpful: $error')),
      );
    }
  }

  Future<void> _toggleSaved(CommunityPost post) async {
    await CommunityStore.instance.toggleSaved(post.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        CommunityStore.instance,
        AppLanguage.instance,
      ]),
      builder: (context, _) {
        final store = CommunityStore.instance;
        final posts = _visiblePosts;
        return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        centerTitle: true,
        title: _searching
            ? AppKeyboardField(
                autofocus: true,
                enableTidyUp: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: AppLanguage.instance.t('searchCommunity'),
                  hintStyle: const TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : Text(AppLanguage.instance.t('community')),
        actions: [
          IconButton(
            tooltip: AppLanguage.instance.t('communityRules'),
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: _openRules,
          ),
          IconButton(
            tooltip: AppLanguage.instance.t('notifications'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const _CommunityNotificationsPage(),
                ),
              );
            },
            icon: Badge(
              isLabelVisible: store.unreadCount > 0,
              label: Text(
                store.unreadCount > 9 ? '9+' : '${store.unreadCount}',
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            tooltip: _searching
                ? AppLanguage.instance.t('closeSearch')
                : AppLanguage.instance.t('search'),
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _query = '';
                  AppKeyboardController.instance.hide();
                }
              });
            },
          ),
        ],
      ),
      body: store.loading
          ? const Center(child: CircularProgressIndicator())
          : store.loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppLanguage.instance.t('couldNotLoadCommunity'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: store.retry,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                          ),
                          child: Text(AppLanguage.instance.t('tryAgain')),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _SafetyBanner(
                  text: AppLanguage.instance.t('safetyBanner'),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _askCommunity,
                  icon: const Icon(Icons.add),
                  label: Text(AppLanguage.instance.t('askTheCommunity')),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _openRules,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(AppLanguage.instance.t('communityRules')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blueAccent,
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: Colors.blueAccent, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in CommunityFilter.values) ...[
                        ChoiceChip(
                          showCheckmark: false,
                          label: Text(filter.label),
                          selected: _filter == filter,
                          selectedColor: Colors.blueAccent,
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: _filter == filter
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                          side: BorderSide(
                            color: _filter == filter
                                ? Colors.blueAccent
                                : Colors.grey.shade400,
                          ),
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _filter.feedTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (posts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text(
                      _filter.emptyMessage,
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final post in posts) ...[
                    _CommunityPostCard(
                      post: post,
                      userId: _userId,
                      saved: CommunityStore.instance.savedIds.contains(post.id),
                      helpful: post.isHelpfulFor(_userId),
                      onTap: () => _openPost(post),
                      onToggleHelpful: () => _toggleHelpful(post),
                      onToggleSaved: () => _toggleSaved(post),
                      onSafetyChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
        );
      },
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE5E5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFC62828)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFB71C1C),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MentionField extends StatefulWidget {
  const _MentionField({
    required this.controller,
    required this.hintText,
    this.minLines = 1,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hintText;
  final int minLines;
  final int maxLines;
  final TextCapitalization textCapitalization;

  @override
  State<_MentionField> createState() => _MentionFieldState();
}

class _MentionFieldState extends State<_MentionField> {
  List<CommunityMember> _suggestions = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    final before = text.substring(0, cursor);
    final match = RegExp(r'@([A-Za-z0-9_]*)$').firstMatch(before);
    if (match == null) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    final query = match.group(1)!.toLowerCase();
    final next = CommunityStore.instance.mentionable
        .where(
          (member) =>
              member.handle.startsWith(query) ||
              member.displayName.toLowerCase().startsWith(query),
        )
        .take(6)
        .toList();
    setState(() => _suggestions = next);
  }

  void _insert(CommunityMember member) {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0) return;
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    final match = RegExp(r'@([A-Za-z0-9_]*)$').firstMatch(before);
    if (match == null) return;
    final start = match.start;
    final next = '${before.substring(0, start)}@${member.handle} $after';
    final offset = start + member.handle.length + 2;
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset),
    );
    setState(() => _suggestions = []);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                for (final member in _suggestions)
                  ListTile(
                    dense: true,
                    title: Text(member.displayName),
                    subtitle: Text('@${member.handle}'),
                    onTap: () => _insert(member),
                  ),
              ],
            ),
          ),
        AppKeyboardField(
          controller: widget.controller,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          textCapitalization: widget.textCapitalization,
          enableTidyUp: true,
          enablePredictions: true,
          predictionSurface: 'community',
          decoration: InputDecoration(
            hintText: widget.hintText,
            filled: true,
            fillColor: const Color(0xFFF2F4F7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _SafetyAction {
  static const report = 'report';
  static const block = 'block';
}

class _SafetyActionsButton extends StatelessWidget {
  const _SafetyActionsButton({
    required this.post,
    required this.userId,
    required this.onChanged,
    this.iconColor,
    this.popOnHide = false,
  });

  final CommunityPost post;
  final String userId;
  final VoidCallback onChanged;
  final Color? iconColor;
  final bool popOnHide;

  bool get _isOwnPost => post.authorId == userId;

  Future<void> _onSelected(BuildContext context, String action) async {
    if (action == _SafetyAction.report) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Report this conversation?'),
          content: const Text(
            'This will hide the post from your feed. Use this if the conversation is harmful, spam, or unsafe.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
              ),
              child: const Text('Report'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await CommunityStore.instance.reportPost(post.id);
      onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks. This conversation was reported and hidden from your feed.'),
        ),
      );
      if (popOnHide) Navigator.pop(context);
      return;
    }

    if (action == _SafetyAction.block) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Block this person?'),
          content: const Text(
            'You will no longer see posts from this person in your community feed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
              ),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await CommunityStore.instance.blockAuthor(post.authorId);
      onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This person is blocked. You will not see their posts.'),
        ),
      );
      if (popOnHide) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isOwnPost) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert, color: iconColor),
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _SafetyAction.report,
          child: Text('Report'),
        ),
        PopupMenuItem(
          value: _SafetyAction.block,
          child: Text('Block'),
        ),
      ],
    );
  }
}

class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({
    required this.post,
    required this.userId,
    required this.saved,
    required this.helpful,
    required this.onTap,
    required this.onToggleHelpful,
    required this.onToggleSaved,
    required this.onSafetyChanged,
  });

  final CommunityPost post;
  final String userId;
  final bool saved;
  final bool helpful;
  final VoidCallback onTap;
  final VoidCallback onToggleHelpful;
  final VoidCallback onToggleSaved;
  final VoidCallback onSafetyChanged;

  @override
  Widget build(BuildContext context) {
    final replyLabel = post.displayedReplyCount == 1
        ? '1 reply'
        : '${post.displayedReplyCount} replies';
    final helpfulLabel =
        '${post.helpfulCount} helpful';
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.blueAccent,
                    child: Text(
                      post.author.isEmpty ? '?' : post.author[0].toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      post.roleLine,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _SafetyActionsButton(
                    post: post,
                    userId: userId,
                    onChanged: onSafetyChanged,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text.rich(
                mentionTextSpan(
                  post.text,
                  TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: Colors.grey.shade800,
                  ),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in post.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F4F7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 4),
                  Text(
                    replyLabel,
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                  const SizedBox(width: 14),
                  InkWell(
                    onTap: onToggleHelpful,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            helpful ? Icons.favorite : Icons.favorite_border,
                            size: 18,
                            color: helpful
                                ? const Color(0xFFE53935)
                                : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            helpfulLabel,
                            style: TextStyle(color: Colors.grey.shade800),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: saved ? 'Remove save' : 'Save conversation',
                    onPressed: onToggleSaved,
                    icon: Icon(
                      saved ? Icons.bookmark : Icons.bookmark_border,
                      color: saved ? Colors.blueAccent : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AskCommunityPage extends StatefulWidget {
  const _AskCommunityPage({required this.authorName});

  final String authorName;

  @override
  State<_AskCommunityPage> createState() => _AskCommunityPageState();
}

class _AskCommunityPageState extends State<_AskCommunityPage> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  CommunityRole _role = CommunityRole.recoveryMember;
  final Set<String> _tags = {};
  bool _saving = false;
  bool _symptomsCleared = false;

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<bool> _runSymptomsTriage() async {
    final urgent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Before you post in Symptoms'),
          content: const Text(
            'Are you experiencing severe or worsening symptoms, chest pain, trouble breathing, uncontrolled bleeding, or feel unsafe?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
              ),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
    if (!mounted) return false;
    if (urgent == true) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const _UrgentCarePage()),
      );
      return false;
    }
    return urgent == false;
  }

  Future<void> _selectSymptomsTag(bool selected) async {
    if (!selected) {
      setState(() {
        _tags.remove('Symptoms');
        _symptomsCleared = false;
      });
      return;
    }
    final allowed = await _runSymptomsTriage();
    if (!mounted) return;
    if (allowed) {
      setState(() {
        _tags.add('Symptoms');
        _symptomsCleared = true;
      });
    }
  }

  Future<void> _post() async {
    final body = _text.text.trim();
    var title = _title.text.trim();
    if (body.isEmpty && title.isEmpty) return;
    if (_tags.contains('Symptoms') && !_symptomsCleared) {
      final allowed = await _runSymptomsTriage();
      if (!allowed) return;
      _symptomsCleared = true;
    }
    if (title.isEmpty) title = CommunityPost._titleFromText(body);
    final user = FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to post.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await CommunityStore.instance.addPost(
        CommunityPost(
          id: 'new',
          author: widget.authorName,
          authorId: user.uid,
          role: _role,
          title: title,
          text: body.isEmpty ? title : body,
          createdAt: DateTime.now(),
          tags: _tags.toList(),
        ),
      );
      TypingPredictionStore.instance.learnFromCommitted(
        [title, body].where((part) => part.trim().isNotEmpty).join('. '),
        surface: 'community',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: Text(AppLanguage.instance.t('askTheCommunity')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              AppLanguage.instance.t('iAmA'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final role in CommunityRole.values)
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(role.label),
                    selected: _role == role,
                    selectedColor: Colors.blueAccent,
                    labelStyle: TextStyle(
                      color: _role == role ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _role = role),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _MentionField(
              controller: _title,
              hintText: AppLanguage.instance.t('titleForQuestion'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            _MentionField(
              controller: _text,
              hintText: AppLanguage.instance.t('writeQuestion'),
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            Text(
              AppLanguage.instance.t('tags'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in communityTagOptions)
                  FilterChip(
                    showCheckmark: false,
                    label: Text(AppLanguage.instance.tagLabel(tag)),
                    selected: _tags.contains(tag),
                    selectedColor: Colors.blueAccent.shade100,
                    onSelected: (selected) {
                      if (tag == 'Symptoms') {
                        _selectSymptomsTag(selected);
                        return;
                      }
                      setState(() {
                        if (selected) {
                          _tags.add(tag);
                        } else {
                          _tags.remove(tag);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _post,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(AppLanguage.instance.t('post')),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityPostPage extends StatefulWidget {
  const _CommunityPostPage({
    required this.postId,
    required this.authorName,
  });

  final String postId;
  final String authorName;

  @override
  State<_CommunityPostPage> createState() => _CommunityPostPageState();
}

class _CommunityPostPageState extends State<_CommunityPostPage> {
  final _reply = TextEditingController();
  final _ai = AiChatService();

  var _showingTranslation = false;
  var _translating = false;
  String? _translatedTitle;
  String? _translatedText;
  String? _translatedForLang;
  final _translatedReplies = <String, String>{};
  List<CommunityReply> _latestReplies = const [];

  CommunityPost? get _post {
    for (final post in CommunityStore.instance.posts) {
      if (post.id == widget.postId) return post;
    }
    return null;
  }

  String get _userId {
    return FirebaseAuth.instance.currentUser?.uid ?? 'local';
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to reply.')),
      );
      return;
    }
    final allowed = await ensureCommunityRulesAccepted(context);
    if (!allowed || !mounted) return;
    try {
      await CommunityStore.instance.addReply(
        widget.postId,
        CommunityReply(
          id: 'new',
          author: widget.authorName,
          text: text,
          createdAt: DateTime.now(),
        ),
      );
      TypingPredictionStore.instance.learnFromCommitted(
        text,
        surface: 'community',
      );
      _reply.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reply: $error')),
      );
    }
  }

  Future<void> _toggleHelpful() async {
    await CommunityStore.instance.toggleHelpful(widget.postId, _userId);
    if (mounted) setState(() {});
  }

  Future<void> _toggleSaved() async {
    await CommunityStore.instance.toggleSaved(widget.postId);
    if (mounted) setState(() {});
  }

  Future<void> _toggleTranslation(CommunityPost post) async {
    if (_translating) return;
    if (_showingTranslation) {
      setState(() => _showingTranslation = false);
      return;
    }

    final langCode = AppLanguage.instance.code;
    final targetLanguage = AppLanguage.instance.englishName;
    final replies = _latestReplies;
    final cacheReady = _translatedForLang == langCode &&
        _translatedTitle != null &&
        _translatedText != null &&
        replies.every((reply) => _translatedReplies.containsKey(reply.id));
    if (cacheReady) {
      setState(() => _showingTranslation = true);
      return;
    }

    setState(() => _translating = true);
    try {
      final texts = <String, String>{
        'title': post.title,
        'text': post.text,
        for (final reply in replies) 'reply_${reply.id}': reply.text,
      };
      final translated = await _ai.translateTexts(
        texts: texts,
        targetLanguage: targetLanguage,
      );
      if (!mounted) return;
      setState(() {
        _translatedTitle = translated['title'] ?? post.title;
        _translatedText = translated['text'] ?? post.text;
        for (final reply in replies) {
          _translatedReplies[reply.id] =
              translated['reply_${reply.id}'] ?? reply.text;
        }
        _translatedForLang = langCode;
        _showingTranslation = true;
        _translating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _translating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.instance.t('translateFailed', {'error': '$error'}),
          ),
        ),
      );
    }
  }

  Widget _translateButton(CommunityPost post) {
    final t = AppLanguage.instance.t;
    final label = _translating
        ? t('translatingPost')
        : _showingTranslation
            ? t('showOriginal')
            : t('translatePost');
    return OutlinedButton.icon(
      onPressed: _translating ? null : () => _toggleTranslation(post),
      icon: _translating
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              _showingTranslation
                  ? Icons.undo
                  : Icons.translate,
            ),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.blueAccent,
        side: const BorderSide(color: Colors.blueAccent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        CommunityStore.instance,
        AppLanguage.instance,
      ]),
      builder: (context, _) {
        final post = _post;
        if (post == null) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.blueAccent,
              title: Text(AppLanguage.instance.t('post')),
            ),
            body: CommunityStore.instance.loading
                ? const Center(child: CircularProgressIndicator())
                : const Center(child: Text('This post is no longer available.')),
          );
        }

        final saved = CommunityStore.instance.savedIds.contains(post.id);
        final helpful = post.isHelpfulFor(_userId);
        final title = _showingTranslation
            ? (_translatedTitle ?? post.title)
            : post.title;
        final body = _showingTranslation
            ? (_translatedText ?? post.text)
            : post.text;

        return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: Text(post.role.label),
        actions: [
          IconButton(
            tooltip: _showingTranslation
                ? AppLanguage.instance.t('showOriginal')
                : AppLanguage.instance.t('translatePost'),
            onPressed:
                _translating ? null : () => _toggleTranslation(post),
            icon: Icon(
              _showingTranslation ? Icons.undo : Icons.translate,
            ),
          ),
          IconButton(
            tooltip: saved ? 'Remove save' : 'Save conversation',
            onPressed: _toggleSaved,
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
          ),
          _SafetyActionsButton(
            post: post,
            userId: _userId,
            iconColor: Colors.white,
            popOnHide: true,
            onChanged: () {
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.blueAccent,
                      child: Text(
                        post.author[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.roleLine,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text.rich(
                            mentionTextSpan(
                              body,
                              const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (post.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in post.tags)
                        Chip(
                          label: Text(
                            _showingTranslation
                                ? AppLanguage.instance.tagLabel(tag)
                                : tag,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _translateButton(post),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _toggleHelpful,
                    icon: Icon(
                      helpful ? Icons.favorite : Icons.favorite_border,
                      color: helpful ? const Color(0xFFE53935) : null,
                    ),
                    label: Text('${post.helpfulCount} helpful'),
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<CommunityReply>>(
                  stream: CommunityStore.instance.repliesStream(widget.postId),
                  builder: (context, snapshot) {
                    final replies = snapshot.data ?? const <CommunityReply>[];
                    _latestReplies = replies;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          replies.isEmpty
                              ? 'Replies'
                              : 'Replies (${replies.length})',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            replies.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: CircularProgressIndicator(),
                          )
                        else if (replies.isEmpty)
                          const Text('No replies yet. Be the first to help.')
                        else
                          for (final reply in replies) ...[
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFFE3F2FD),
                                  child: Text(reply.author[0].toUpperCase()),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reply.author,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text.rich(
                                        mentionTextSpan(
                                          _showingTranslation
                                              ? (_translatedReplies[reply.id] ??
                                                  reply.text)
                                              : reply.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _MentionField(
                      controller: _reply,
                      hintText: 'Write a reply. Use @name to mention someone.',
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Post reply',
                    onPressed: _sendReply,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
        );
      },
    );
  }
}

class _UrgentCarePage extends StatelessWidget {
  const _UrgentCarePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: const Text('Urgent care'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE5E5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'This community cannot help with a medical emergency. Get in-person or phone care now.',
              style: TextStyle(
                color: Color(0xFFB71C1C),
                fontWeight: FontWeight.w700,
                height: 1.35,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'If you have severe or worsening symptoms, chest pain, trouble breathing, uncontrolled bleeding, or feel unsafe:',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 16),
          const _UrgentStep(
            number: '1',
            text: 'Call your local emergency number now.',
          ),
          const _UrgentStep(
            number: '2',
            text: 'Contact your care team or the hospital number you were given at discharge.',
          ),
          const _UrgentStep(
            number: '3',
            text: 'Stay with someone if you can, and do not wait for replies in this app.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Back to community'),
          ),
        ],
      ),
    );
  }
}

class _UrgentStep extends StatelessWidget {
  const _UrgentStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFFC62828),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _CommunityNotificationsPage extends StatelessWidget {
  const _CommunityNotificationsPage();

  IconData _iconFor(String type) {
    switch (type) {
      case 'mention':
        return Icons.alternate_email;
      case 'helpful':
        return Icons.favorite;
      case 'saved_reply':
        return Icons.bookmark;
      case 'comment_reply':
        return Icons.subdirectory_arrow_right;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CommunityStore.instance,
      builder: (context, _) {
        final items = CommunityStore.instance.notifications;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blueAccent,
            title: const Text('Notifications'),
            actions: [
              if (CommunityStore.instance.unreadCount > 0)
                TextButton(
                  onPressed: CommunityStore.instance.markAllNotificationsRead,
                  child: const Text(
                    'Mark all read',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
          body: items.isEmpty
              ? const Center(
                  child: Text('No notifications yet.'),
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: Icon(
                        _iconFor(item.type),
                        color: item.read
                            ? Colors.grey
                            : Colors.blueAccent,
                      ),
                      title: Text(
                        item.title,
                        style: TextStyle(
                          fontWeight:
                              item.read ? FontWeight.w500 : FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        item.postTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        await CommunityStore.instance
                            .markNotificationRead(item.id);
                        if (!context.mounted) return;
                        final name =
                            await CommunityStore.instance.resolveAuthorName();
                        if (!context.mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _CommunityPostPage(
                              postId: item.postId,
                              authorName: name,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}

class _CommunityRulesPage extends StatelessWidget {
  const _CommunityRulesPage({this.requireAccept = false});

  final bool requireAccept;

  static const _rules = <String>[
    'Share personal experience, not medical advice.',
    'Do not diagnose someone else or tell them what treatment to take.',
    'Be kind. This is a recovery space.',
    'Urgent symptoms belong with your care team or local emergency services, not this feed.',
    'Report or block anything harmful.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: Text(AppLanguage.instance.t('communityRules')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            AppLanguage.instance.t('communityRules'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            AppLanguage.instance.t('rulesIntro'),
            style: TextStyle(
              fontSize: 16,
              height: 1.4,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _rules.length; i++) ...[
            _RuleRow(number: '${i + 1}', text: _rules[i]),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          if (requireAccept)
            FilledButton(
              onPressed: () async {
                await CommunityStore.instance.acceptRules();
                if (context.mounted) Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('I understand'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Colors.blueAccent,
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
      ],
    );
  }
}
