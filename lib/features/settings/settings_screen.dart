import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/music/audd_client.dart';
import '../../core/music/music_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _ctl = TextEditingController();
  bool _show = false;
  bool _loaded = false;
  bool _testing = false;
  String? _result;
  bool _resultOk = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final t = _ctl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _testing = true;
      _result = null;
    });
    final client = AuddClient();
    try {
      await client.testToken(t);
      _resultOk = true;
      _result = 'Token OK';
    } on AuddApiError catch (e) {
      _resultOk = false;
      _result = e.message;
    } on AuddNetworkError catch (e) {
      _resultOk = false;
      _result = e.message;
    } finally {
      client.close();
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(auddTokenProvider);
    if (!_loaded && token.hasValue) {
      _loaded = true;
      _ctl.text = token.value ?? '';
    }
    final clips = ref.watch(clipCountProvider).value ?? 3;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Music recognition (AudD)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'The only feature that uses the network. When you start a scan, '
            'short audio clips (never file names, video or thumbnails) are '
            'sent to api.audd.io with your token. AudD bills per request.',
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: TextField(
              controller: _ctl,
              obscureText: !_show,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'AudD API token',
                border: const OutlineInputBorder(),
                suffixIcon: TextButton(
                  onPressed: () => setState(() => _show = !_show),
                  child: Text(_show ? 'Hide' : 'Show'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: () async {
                  final t = _ctl.text.trim();
                  if (t.isEmpty) return;
                  await ref.read(auddTokenProvider.notifier).save(t);
                  if (!mounted) return;
                  setState(() {
                    _resultOk = true;
                    _result = 'Saved';
                  });
                },
                child: const Text('Save'),
              ),
              OutlinedButton(
                onPressed: () async {
                  await ref.read(auddTokenProvider.notifier).remove();
                  _ctl.clear();
                  if (!mounted) return;
                  setState(() => _result = null);
                },
                child: const Text('Remove'),
              ),
              OutlinedButton(
                onPressed: _testing ? null : _test,
                child: Text(_testing ? 'Testing...' : 'Test token'),
              ),
              if (_result != null)
                Text(
                  _result!,
                  style: TextStyle(
                    color: _resultOk
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Clips per video',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
            ],
            selected: {clips},
            onSelectionChanged: (s) =>
                ref.read(clipCountProvider.notifier).set(s.first),
          ),
        ],
      ),
    );
  }
}
