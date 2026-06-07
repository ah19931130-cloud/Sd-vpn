import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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
  Map<String, dynamic>? _extractedData;
  String _statusMessage = 'Tap to simulate AI processing';
  bool _isProcessing = false;

  String get openAiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  Future<void> _simulateProcessing() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing sample audio...';
    });

    // Simulate a short delay to mimic processing
    await Future.delayed(const Duration(seconds: 2));

    // Mock data to show the UI in action
    setState(() {
      _extractedData = {
        'tasks': [
          {'title': 'Prepare presentation', 'dueDate': DateTime.now().add(const Duration(days: 1)).toIso8601String()},
        ],
        'events': [
          {'summary': 'Marketing team meeting', 'start': DateTime.now().add(const Duration(days: 1)).toIso8601String(), 'end': DateTime.now().add(const Duration(days: 1, hours: 1)).toIso8601String()},
        ],
        'notes': ['Review the contract after the meeting']
      };
      _statusMessage = 'Done!';
      _isProcessing = false;
    });
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
              onTap: _isProcessing ? null : _simulateProcessing,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: _isProcessing ? Colors.grey : Colors.deepPurple,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isProcessing ? Icons.hourglass_top : Icons.play_arrow,
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
    final tasks = List<Map<String, dynamic>>.from(_extractedData!['tasks'] ?? []);
    final events = List<Map<String, dynamic>>.from(_extractedData!['events'] ?? []);
    final notes = List<String>.from(_extractedData!['notes'] ?? []);
    final dateFormat = DateFormat('yyyy/MM/dd HH:mm');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...events.map((event) => Card(
              color: Colors.blue.shade50,
              child: ListTile(
                leading: const Icon(Icons.event, color: Colors.blue),
                title: Text(event['summary'] ?? 'Event'),
                subtitle: Text(
                  '${dateFormat.format(DateTime.parse(event['start']))} → ${dateFormat.format(DateTime.parse(event['end']))}',
                ),
              ),
            )),
        ...tasks.map((task) => Card(
              color: Colors.orange.shade50,
              child: ListTile(
                leading: const Icon(Icons.task_alt, color: Colors.orange),
                title: Text(task['title'] ?? 'Task'),
                subtitle: task['dueDate'] != null
                    ? Text('Due: ${dateFormat.format(DateTime.parse(task['dueDate']))}')
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
                  const Text('📝 Notes', style: TextStyle(fontWeight: FontWeight.bold)),
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
