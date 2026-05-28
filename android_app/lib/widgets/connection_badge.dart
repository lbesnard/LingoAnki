import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/sync_manager.dart';

class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SyncManager.instance,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final online = SyncManager.instance.isOnline;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                online ? Icons.cloud_done : Icons.cloud_off,
                size: 18,
                color: online ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 4),
              Text(
                online ? l10n.serverOnline : l10n.serverOffline,
                style: TextStyle(
                  fontSize: 12,
                  color: online ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
