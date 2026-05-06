import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionBadge extends StatefulWidget {
  const ConnectionBadge({super.key});

  @override
  State<ConnectionBadge> createState() => _ConnectionBadgeState();
}

class _ConnectionBadgeState extends State<ConnectionBadge> {
  bool _online = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _check();
    // Re-check every 15 seconds
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('server_url') ?? '';
      if (serverUrl.isEmpty) {
        setState(() => _online = false);
        return;
      }
      final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
      // A lightweight ping: any HTTP response means the server is up
      await http
          .get(Uri.parse('$base/api/login'))
          .timeout(const Duration(seconds: 5));
      setState(() => _online = true);
    } catch (_) {
      setState(() => _online = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _check,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _online ? Icons.cloud_done : Icons.cloud_off,
              size: 18,
              color: _online ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 4),
            Text(
              _online ? 'Server online' : 'Server offline',
              style: TextStyle(
                fontSize: 12,
                color: _online ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
