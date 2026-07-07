// storage.dart — 本地存储层：章节、记忆、快照，全部存为 JSON 文件
// 不依赖后端，所有数据存在设备本地 (path_provider)。

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_client.dart';

// ── 数据模型 ────────────────────────────────────────────────────────

class Chapter {
  final String id;
  String title;
  String content;
  final DateTime createdAt;
  DateTime updatedAt;

  Chapter({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
    id: j['id'] as String,
    title: j['title'] as String? ?? '未命名章节',
    content: j['content'] as String? ?? '',
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );

  factory Chapter.create(String title) {
    final now = DateTime.now();
    return Chapter(
      id: 'ch_${now.millisecondsSinceEpoch}',
      title: title, content: '',
      createdAt: now, updatedAt: now,
    );
  }
}

class Memory {
  final String id;
  String kind; // character / worldbuilding / plot / foreshadow / lore / other
  String title;
  String content;
  final DateTime createdAt;

  Memory({
    required this.id, required this.kind,
    required this.title, required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'kind': kind, 'title': title, 'content': content,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Memory.fromJson(Map<String, dynamic> j) => Memory(
    id: j['id'] as String,
    kind: j['kind'] as String? ?? 'other',
    title: j['title'] as String? ?? '',
    content: j['content'] as String? ?? '',
    createdAt: DateTime.parse(j['createdAt'] as String),
  );

  factory Memory.create({required String kind, required String title,
      required String content}) {
    return Memory(
      id: 'mem_${DateTime.now().millisecondsSinceEpoch}',
      kind: kind, title: title, content: content,
      createdAt: DateTime.now(),
    );
  }
}

class Checkpoint {
  final String id;
  final String chapterId;
  final String chapterTitle;
  final String content;
  String message;
  final DateTime createdAt;

  Checkpoint({
    required this.id, required this.chapterId,
    required this.chapterTitle, required this.content,
    required this.message, required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'chapterId': chapterId,
    'chapterTitle': chapterTitle, 'content': content,
    'message': message, 'createdAt': createdAt.toIso8601String(),
  };

  factory Checkpoint.fromJson(Map<String, dynamic> j) => Checkpoint(
    id: j['id'] as String, chapterId: j['chapterId'] as String? ?? '',
    chapterTitle: j['chapterTitle'] as String? ?? '',
    content: j['content'] as String? ?? '',
    message: j['message'] as String? ?? '',
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

// ── 本地存储 ────────────────────────────────────────────────────────

class LocalStorage {
  static LocalStorage? _instance;
  static LocalStorage get instance => _instance ??= LocalStorage._();
  LocalStorage._();

  Future<Directory> get _dir async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/novel_agent');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  File _file(Directory dir, String name) => File('${dir.path}/$name');

  // ── 通用 JSON 读写 ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _readList(String filename) async {
    final dir = await _dir;
    final f = _file(dir, filename);
    if (!f.existsSync()) return [];
    try {
      return (jsonDecode(f.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) { return []; }
  }

  Future<void> _writeList(String filename, List<Map<String, dynamic>> data) async {
    final dir = await _dir;
    _file(dir, filename).writeAsStringSync(jsonEncode(data));
  }

  // ── 章节 CRUD ─────────────────────────────────────────────────────

  Future<List<Chapter>> listChapters() async {
    final raw = await _readList('chapters.json');
    return raw.map(Chapter.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> saveChapter(Chapter ch) async {
    final all = await listChapters();
    final idx = all.indexWhere((c) => c.id == ch.id);
    ch.updatedAt = DateTime.now();
    if (idx >= 0) all[idx] = ch; else all.insert(0, ch);
    await _writeList('chapters.json', all.map((c) => c.toJson()).toList());
  }

  Future<void> deleteChapter(String id) async {
    final all = await listChapters();
    all.removeWhere((c) => c.id == id);
    await _writeList('chapters.json', all.map((c) => c.toJson()).toList());
    // 同时删除该章节的所有快照
    final cps = await listCheckpoints();
    final remaining = cps.where((c) => c.chapterId != id).toList();
    await _writeList('checkpoints.json', remaining.map((c) => c.toJson()).toList());
  }

  // ── 记忆 CRUD ─────────────────────────────────────────────────────

  Future<List<Memory>> listMemories() async {
    final raw = await _readList('memories.json');
    return raw.map(Memory.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveMemory(Memory m) async {
    final all = await listMemories();
    final idx = all.indexWhere((x) => x.id == m.id);
    if (idx >= 0) all[idx] = m; else all.insert(0, m);
    await _writeList('memories.json', all.map((x) => x.toJson()).toList());
  }

  Future<void> deleteMemory(String id) async {
    final all = await listMemories();
    all.removeWhere((m) => m.id == id);
    await _writeList('memories.json', all.map((m) => m.toJson()).toList());
  }

  // ── 快照 CRUD ─────────────────────────────────────────────────────

  Future<List<Checkpoint>> listCheckpoints() async {
    final raw = await _readList('checkpoints.json');
    return raw.map(Checkpoint.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<Checkpoint> createCheckpoint(Chapter ch, String message) async {
    final cp = Checkpoint(
      id: 'cp_${DateTime.now().millisecondsSinceEpoch}',
      chapterId: ch.id, chapterTitle: ch.title,
      content: ch.content, message: message,
      createdAt: DateTime.now(),
    );
    final all = await listCheckpoints();
    all.insert(0, cp);
    await _writeList('checkpoints.json', all.map((c) => c.toJson()).toList());
    return cp;
  }

  Future<void> restoreCheckpoint(Checkpoint cp) async {
    final chapters = await listChapters();
    final idx = chapters.indexWhere((c) => c.id == cp.chapterId);
    if (idx < 0) return;
    chapters[idx]
      ..content = cp.content
      ..updatedAt = DateTime.now();
    await _writeList('chapters.json', chapters.map((c) => c.toJson()).toList());
  }

  Future<void> deleteCheckpoint(String id) async {
    final all = await listCheckpoints();
    all.removeWhere((c) => c.id == id);
    await _writeList('checkpoints.json', all.map((c) => c.toJson()).toList());
  }

  // ── AI 供应商设置 ─────────────────────────────────────────────────

  Future<AiProvider?> loadProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('ai_provider');
    if (json == null) return null;
    try {
      return AiProvider.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) { return null; }
  }

  Future<void> saveProvider(AiProvider p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', jsonEncode(p.toJson()));
  }

  // ── 历史会话 CRUD ─────────────────────────────────────────────────

  Future<List<ConversationRecord>> listConversations() async {
    final raw = await _readList('conversations.json');
    return raw.map(ConversationRecord.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> saveConversation(ConversationRecord conv) async {
    final all = await listConversations();
    conv.updatedAt = DateTime.now();
    final idx = all.indexWhere((c) => c.id == conv.id);
    if (idx >= 0) all[idx] = conv; else all.insert(0, conv);
    // 最多保留 100 条
    final trimmed = all.take(100).toList();
    await _writeList('conversations.json',
        trimmed.map((c) => c.toJson()).toList());
  }

  Future<void> deleteConversation(String id) async {
    final all = await listConversations();
    all.removeWhere((c) => c.id == id);
    await _writeList('conversations.json',
        all.map((c) => c.toJson()).toList());
  }
}

// ── 历史会话记录 ─────────────────────────────────────────────────────

class ConversationMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;

  const ConversationMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ConversationMessage.fromJson(Map<String, dynamic> j) =>
      ConversationMessage(
        role: j['role'] as String? ?? 'user',
        content: j['content'] as String? ?? '',
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

class ConversationRecord {
  final String id;
  String title;
  List<ConversationMessage> messages;
  final DateTime createdAt;
  DateTime updatedAt;
  String providerName;
  String modelName;

  ConversationRecord({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    required this.providerName,
    required this.modelName,
  });

  /// 自动从第一条用户消息提取标题
  static String titleFrom(List<ConversationMessage> msgs) {
    final first = msgs.firstWhere(
      (m) => m.role == 'user' && m.content.isNotEmpty,
      orElse: () => ConversationMessage(
        role: 'user', content: '新对话', timestamp: DateTime.now()),
    );
    final text = first.content.replaceAll('\n', ' ').trim();
    return text.length > 18 ? '${text.substring(0, 18)}…' : text;
  }

  /// 最后一条助手消息的文本预览
  String get preview {
    final last = messages.lastWhere(
      (m) => m.role == 'assistant' && m.content.isNotEmpty,
      orElse: () => ConversationMessage(
        role: 'assistant', content: '', timestamp: DateTime.now()),
    );
    final text = last.content.replaceAll('\n', ' ').trim();
    return text.length > 40 ? '${text.substring(0, 40)}…' : text;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'providerName': providerName,
    'modelName': modelName,
  };

  factory ConversationRecord.fromJson(Map<String, dynamic> j) {
    final msgs = (j['messages'] as List? ?? [])
        .map((e) =>
            ConversationMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    return ConversationRecord(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '对话',
      messages: msgs,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      providerName: j['providerName'] as String? ?? '',
      modelName: j['modelName'] as String? ?? '',
    );
  }

  factory ConversationRecord.create({
    required String providerName,
    required String modelName,
  }) {
    final now = DateTime.now();
    return ConversationRecord(
      id: 'conv_${now.millisecondsSinceEpoch}',
      title: '新对话',
      messages: [],
      createdAt: now,
      updatedAt: now,
      providerName: providerName,
      modelName: modelName,
    );
  }
}
