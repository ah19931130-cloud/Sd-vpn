import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    // ضع خيارات Firebase الخاصة بمشروعك هنا إن لم تستخدم `google-services.json` التلقائي
  );
  runApp(const Voice2ActionApp());
}

class Voice2ActionApp extends StatelessWidget {
  const Voice2ActionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice2Action',
      theme: ThemeData(primarySwatch: Colors.deepPurple, useMaterial3: true),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentRecordingPath;
  String? _downloadUrl;

  // يخزن آخر مستند تمت معالجته (مهام، مواعيد، ملاحظات)
  Map<String, dynamic>? _extractedData;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      setState(() {
        _isRecording = true;
        _currentRecordingPath = path;
      });
    }
  }

  Future<void> _stopAndUpload() async {
    if (!_isRecording) return;
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path == null) return;

    // رفع الملف الصوتي إلى Firebase Storage
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('audios/${DateTime.now().millisecondsSinceEpoch}.m4a');
    await storageRef.putFile(File(path));
    final downloadUrl = await storageRef.getDownloadURL();

    // إنشاء مستند جديد في Firestore ليبدأ تشغيل الدوال السحابية
    await FirebaseFirestore.instance.collection('recordings').add({
      'audioUrl': downloadUrl,
      'status': 'uploaded',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // الاستماع إلى آخر مستند تمت إضافته لاستقبال النتائج مباشرة
    FirebaseFirestore.instance
        .collection('recordings')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data();
        if (data['status'] == 'extracted') {
          setState(() {
            _extractedData = data;
            _downloadUrl = data['audioUrl'];
          });
        }
      }
    });

    setState(() => _currentRecordingPath = null);
  }

  Future<void> _addToCalendar(Map<String, dynamic> event) async {
    // للعرض: إنشاء رابط Google Calendar عام (بسيط جداً)
    final title = Uri.encodeComponent(event['summary'] ?? 'Event');
    final start = event['start'] ?? DateTime.now().toIso8601String();
    final end = event['end'] ?? DateTime.now().add(const Duration(hours: 1)).toIso8601String();
    final url =
        'https://calendar.google.com/calendar/render?action=TEMPLATE&text=$title&dates=${start.replaceAll(RegExp(r'[-:.]'), '')}/${end.replaceAll(RegExp(r'[-:.]'), '')}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎙️ Voice2Action'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // زر التسجيل الكبير
            GestureDetector(
              onTap: _isRecording ? _stopAndUpload : _startRecording,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : Colors.deepPurple,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isRecording ? 'جاري التسجيل...' : 'اضغط للتحدث',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            // عرض المهام والمواعيد بعد المعالجة
            if (_extractedData != null) Expanded(child: _buildExtractedView()),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractedView() {
    final tasks = List<Map<String, dynamic>>.from(_extractedData!['tasks'] ?? []);
    final events = List<Map<String, dynamic>>.from(_extractedData!['events'] ?? []);
    final notes = List<String>.from(_extractedData!['notes'] ?? []);
    final dateFormat = DateFormat('yyyy/MM/dd HH:mm');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (events.isNotEmpty)
          ...events.map((event) => Card(
                color: Colors.blue.shade50,
                child: ListTile(
                  leading: const Icon(Icons.event, color: Colors.blue),
                  title: Text(event['summary'] ?? 'موعد'),
                  subtitle: Text(
                    '${dateFormat.format(DateTime.parse(event['start']))} → ${dateFormat.format(DateTime.parse(event['end']))}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () => _addToCalendar(event),
                  ),
                ),
              )),
        if (tasks.isNotEmpty)
          ...tasks.map((task) => Card(
                color: Colors.orange.shade50,
                child: ListTile(
                  leading: const Icon(Icons.task_alt, color: Colors.orange),
                  title: Text(task['title'] ?? 'مهمة'),
                  subtitle: task['dueDate'] != null
                      ? Text('موعد التسليم: ${dateFormat.format(DateTime.parse(task['dueDate']))}')
                      : const Text('بدون موعد محدد'),
                ),
              )),
        if (notes.isNotEmpty)
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📝 ملاحظات', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...notes.map((note) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• $note'),
                      )),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
