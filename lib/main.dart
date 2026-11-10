import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';

void main() => runApp(const VpnApp());

class VpnApp extends StatelessWidget {
  const VpnApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Home VPN',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'GatewayRoboto',
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xff71d7c0),
      scaffoldBackgroundColor: const Color(0xff10191d),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    ),
    home: const Dashboard(),
  );
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, this.api});
  final VpnApi? api;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late final VpnApi _api;
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _selected = <String>{};
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _relays = [];
  String _status = '';
  String _message = '';
  String _relay = 'configured';
  int _minutes = 15;
  bool _loggedIn = false;
  bool _busy = true;
  bool _error = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? VpnApi();
    _run(() async {
      try {
        await _api.request('session');
      } on ApiException catch (error) {
        if (error.unauthorized) return;
        rethrow;
      }
      if (mounted) setState(() => _loggedIn = true);
      await _refresh();
    });
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_loggedIn && !_busy) _run(_refresh);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _username.dispose();
    _password.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (mounted) setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (error is ApiException && error.unauthorized) _loggedIn = false;
        _message = error.toString();
        _error = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final devices = await _api.request('devices');
    final relays = await _api.request('relays');
    final status = await _api.request('status');
    if (!mounted) return;
    setState(() {
      _devices = (devices['devices'] as List).cast<Map<String, dynamic>>();
      _relays = (relays['relays'] as List).cast<Map<String, dynamic>>();
      _status = status['message'] as String;
      _selected.retainAll(_devices.map((d) => d['address'] as String));
    });
  }

  Future<void> _login() => _run(() async {
    try {
      await _api.login(_username.text, _password.text);
    } finally {
      _password.clear();
    }
    if (mounted) {
      setState(() {
        _loggedIn = true;
        _message = '';
      });
    }
    await _refresh();
  });

  Future<void> _act(String action, {bool all = false}) async {
    if (_busy) return;
    if (action == 'bypass' || action == 'switch' || all) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            action == 'bypass'
                ? 'Use your home ISP?'
                : action == 'switch'
                ? 'Change Mullvad relay?'
                : 'Restore all devices?',
          ),
          content: Text(
            action == 'bypass'
                ? '${all ? 'Every device, including this server' : '${_selected.length} selected device(s)'} '
                      'will use your home public IP for $_minutes minutes. '
                      '${all ? 'This replaces individual timers. ' : ''}'
                      'Home VPN stays on; IPv6 stays blocked.'
                : action == 'switch'
                ? 'Connections may reset. Restarting Mullvad restores the configured default.'
                : 'All temporary bypasses will end immediately.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _run(() async {
      final response = await _api.request(
        action,
        body: {
          if (action != 'switch') 'targets': all ? 'all' : _selected.toList(),
          if (action == 'bypass') 'minutes': _minutes,
          if (action == 'switch') 'relay': _relay,
        },
      );
      if (mounted) {
        setState(() {
          _message = response['message'] as String;
          _error = false;
        });
      }
      await _refresh();
    });
  }

  Widget _panel(String title, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );

  Widget _loginForm() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: _panel(
        'Control room · sign in',
        AutofillGroup(
          child: Column(
            children: [
              TextField(
                controller: _username,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _busy ? null : _login(),
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _dashboard() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Home VPN',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const Text('Your network. Your exceptions.'),
            ],
          ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(_refresh),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await _api.logout();
                        if (mounted) {
                          setState(() {
                            _loggedIn = false;
                            _devices = [];
                            _status = '';
                            _selected.clear();
                            _message = '';
                          });
                        }
                      }),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Text(
        'Temporary bypass uses your home ISP and public IP. '
        'Home VPN stays on. Untunnelled IPv6 stays blocked.',
      ),
      const SizedBox(height: 24),
      _panel(
        'Devices · temporary exceptions',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Passive discovery can miss devices. '
              'Names and handshake observations are not trusted identities.',
            ),
            const SizedBox(height: 12),
            if (_devices.isEmpty) const Text('No devices found. Try Refresh.'),
            for (final device in _devices)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(device['address']),
                onChanged: _busy
                    ? null
                    : (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(device['address'] as String);
                        } else {
                          _selected.remove(device['address']);
                        }
                      }),
                title: Text(device['title'] as String),
                secondary: Icon(
                  device['bypassSeconds'] > 0
                      ? Icons.timer_outlined
                      : Icons.devices,
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                DropdownButton<int>(
                  value: _minutes,
                  items: [5, 15, 30, 60]
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text('$n minutes'),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _minutes = value!),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || _selected.isEmpty
                      ? null
                      : () => _act('bypass'),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Bypass selected'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _selected.isEmpty
                      ? null
                      : () => _act('restore'),
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('Restore selected'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _panel(
        'Mullvad · exit region',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selection is a requested destination, not live status. '
              'Restarting Mullvad restores the configured default.',
            ),
            const SizedBox(height: 12),
            DropdownButton<String>(
              isExpanded: true,
              value: _relay,
              items: _relays
                  .map(
                    (r) => DropdownMenuItem(
                      value: r['id'] as String,
                      child: Text(
                        r['label'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _relay = value!),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _busy ? null : () => _act('switch'),
              child: const Text('Change relay'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _panel('Gateway status', SelectableText(_status)),
      const SizedBox(height: 20),
      _panel(
        'Whole network',
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _act('restore', all: true),
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Restore all devices'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => _act('bypass', all: true),
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Bypass all devices'),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _message,
                        style: TextStyle(
                          color: _error
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                _loggedIn ? _dashboard() : _loginForm(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
