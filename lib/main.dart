import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp();
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
  Map<String, dynamic>? _extractedData;
  String _statusMessage = 'Press the mic and speak';

  String get openAiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const AudioRecorderConfig(),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _statusMessage = 'Recording...';
      });
    }
  }

  Future<void> _stopAndProcess() async {
    if (!_isRecording) return;
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _statusMessage = 'Transcribing...';
    });
    if (path == null) return;

    final transcript = await _transcribeAudio(File(path));
    if (transcript == null) {
      setState(() => _statusMessage = 'Transcription failed');
      return;
    }

    setState(() => _statusMessage = 'Extracting actions...');

    final extracted = await _extractActions(transcript);
    if (extracted == null) {
      setState(() => _statusMessage = 'Extraction failed');
      return;
    }

    await FirebaseFirestore.instance.collection('recordings').add({
      'transcript': transcript,
      ...extracted,
      'createdAt': FieldValue.serverTimestamp(),
    });

    setState(() {
      _extractedData = extracted;
      _statusMessage = 'Done!';
    });
  }

  Future<String?> _transcribeAudio(File file) async {
    try {
      var uri = Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions');
      var request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $openAiKey';
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'ar';
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      var response = await request.send();
      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(await response.stream.bytesToString());
        return jsonResponse['text'];
      }
    } catch (e) {
      print('Whisper error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _extractActions(String transcript) async {
    final today = DateTime.now().toIso8601String();
    final prompt = '''You are an AI assistant that extracts actionable items from Arabic speech transcripts.
Given the transcript, return a JSON object with three arrays: "tasks" (to-do items with a title and optional due date in ISO format), "events" (calendar entries with summary, start, and end if duration is mentioned), and "notes" (general notes).
For dates, convert relative terms like "tomorrow" or "next Monday" to absolute dates based on today's date: $today.
If no date is mentioned for a task, set dueDate to null. Output only valid JSON without any markdown formatting.

Transcript: $transcript''';

    try {
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $openAiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'llama-3.1-8b-instant',
          'messages': [{'role': 'user', 'content': prompt}],
          'response_format': {'type': 'json_object'},
          'temperature': 0,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return jsonDecode(data['choices'][0]['message']['content']);
      }
    } catch (e) {
      print('LLM error: $e');
    }
    return null;
  }

  Future<void> _addToCalendar(Map<String, dynamic> event) async {
    final title = Uri.encodeComponent(event['summary'] ?? 'Event');
    final start =
        event['start'] ?? DateTime.now().toIso8601String();
    final end =
        event['end'] ?? DateTime.now().add(const Duration(hours: 1)).toIso8601String();
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
            GestureDetector(
              onTap: _isRecording ? _stopAndProcess : _startRecording,
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
              _statusMessage,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            if (_extractedData != null)
              Expanded(child: _buildExtractedView()),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractedView() {
    final tasks =
        List<Map<String, dynamic>>.from(_extractedData!['tasks'] ?? []);
    final events =
        List<Map<String, dynamic>>.from(_extractedData!['events'] ?? []);
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
                  title: Text(event['summary'] ?? 'Event'),
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
                  title: Text(task['title'] ?? 'Task'),
                  subtitle: task['dueDate'] != null
                      ? Text(
                          'Due: ${dateFormat.format(DateTime.parse(task['dueDate']))}')
                      : const Text('No due date'),
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
                  const Text('📝 Notes',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ...notes.map((note) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• $note')),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
