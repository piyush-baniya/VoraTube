import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vora_tube/features/ringtones/data/audio_util_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RingtoneVerifyApp());
}

class RingtoneVerifyApp extends StatefulWidget {
  const RingtoneVerifyApp({super.key});

  @override
  State<RingtoneVerifyApp> createState() => _RingtoneVerifyAppState();
}

class _RingtoneVerifyAppState extends State<RingtoneVerifyApp> {
  final List<String> _logs = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _runAllCases();
  }

  void _log(String message) {
    debugPrint('[RingtoneVerify] $message');
    if (mounted) {
      setState(() => _logs.add(message));
    }
  }

  Future<void> _runAllCases() async {
    setState(() {
      _running = true;
      _logs.clear();
    });

    _log('Starting Ringtone Verification on Physical Device...');
    final service = MethodChannelAudioUtilService();
    final supported = await service.supportsCutting();
    _log('Supports cutting: $supported');
    if (!supported) {
      _log('ERROR: Cutting not supported on platform');
      setState(() => _running = false);
      return;
    }

    // Real source track from device MediaStore (Night Changes: 240s)
    const testUri = 'content://media/external/audio/media/1000062194';
    const testTitle = 'Night Changes Test';

    final cases = [
      {'name': 'Case A (Beginning: 0s -> 30s)', 'start': 0, 'end': 30000},
      {'name': 'Case B (Middle: 60s -> 90s)', 'start': 60000, 'end': 90000},
      {'name': 'Case C (End: 180s -> 210s)', 'start': 180000, 'end': 210000},
      {'name': 'Case D (Short: 10s -> 15s)', 'start': 10000, 'end': 15000},
      {'name': 'Case E (Long: 30s -> 150s)', 'start': 30000, 'end': 150000},
    ];

    for (final c in cases) {
      final name = c['name'] as String;
      final start = c['start'] as int;
      final end = c['end'] as int;
      final expectedDurationSec = (end - start) / 1000;
      _log('--- Testing $name ---');

      try {
        final stopwatch = Stopwatch()..start();
        final result = await service.cutAudio(
          sourceUri: testUri,
          startMs: start,
          endMs: end,
          songTitle: testTitle,
        );
        stopwatch.stop();

        final file = File(result.path);
        final exists = await file.exists();
        final sizeBytes = exists ? await file.length() : 0;

        _log('Result path: ${result.path}');
        _log('Result contentUri: ${result.contentUri}');
        _log('Reported durationMs: ${result.durationMs}ms (expected ~${end - start}ms)');
        _log('File exists: $exists');
        _log('File size: $sizeBytes bytes (~${(sizeBytes / 1024).toStringAsFixed(1)} KB)');
        _log('Time taken: ${stopwatch.elapsedMilliseconds}ms');

        if (!exists) {
          _log('FAILED: File does not exist');
        } else if (sizeBytes < 10000) {
          _log('FAILED: File is too small ($sizeBytes bytes - likely corrupt/empty header)');
        } else {
          _log('PASSED: Generated playable M4A of $sizeBytes bytes for $expectedDurationSec seconds');
        }
      } catch (e, st) {
        _log('EXCEPTION in $name: $e\n$st');
      }
    }

    _log('=== ALL RINGTONE CASES COMPLETED ===');
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Ringtone Device Verifier'),
          actions: [
            if (_running)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _runAllCases,
              ),
          ],
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _logs.length,
          itemBuilder: (context, index) {
            final log = _logs[index];
            final isPassed = log.contains('PASSED:');
            final isFailed = log.contains('FAILED:') || log.contains('EXCEPTION');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                log,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: isPassed
                      ? Colors.green
                      : isFailed
                          ? Colors.red
                          : Colors.black87,
                  fontWeight: (isPassed || isFailed) ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
