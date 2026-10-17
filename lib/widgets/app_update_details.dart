import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/app_updates.dart';
import 'common.dart';

/// Installed package metadata and store checks share one controller throughout
/// the app; opening the store always goes through the shell's save guards.
class AppUpdateDetails extends StatelessWidget {
  const AppUpdateDetails({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final updates = scope.updates;
    if (updates == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final installed = updates.installed;
        final checking = updates.status == StoreUpdateStatus.checking;
        final message = switch (updates.status) {
          StoreUpdateStatus.idle => 'Updates werden im Store geprüft.',
          StoreUpdateStatus.checking => 'Im Store wird nach Updates gesucht …',
          StoreUpdateStatus.current => 'Für diese Installation ist im Store kein neueres Update verfügbar.',
          StoreUpdateStatus.available =>
            updates.update?.version == null
                ? 'Ein Update ist im Store verfügbar.'
                : 'Version ${updates.update!.version} ist im Store verfügbar.',
          StoreUpdateStatus.unavailable =>
            updates.errorMessage ??
                'Für diese Installation ist keine Store-Prüfung verfügbar.',
          StoreUpdateStatus.failed => updates.errorMessage ?? 'Die Update-Prüfung ist momentan nicht möglich. Bitte versuche es erneut.',
        };
        return SectionCard(
          title: 'App-Version & Updates',
          children: [
            Text(
              installed == null
                  ? checking || updates.status == StoreUpdateStatus.idle
                        ? 'Installierte Version wird ermittelt …'
                        : 'Installierte Version konnte nicht ermittelt werden.'
                  : 'Version ${installed.version} · Build ${installed.build}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(message)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: checking ? null : () => updates.check(force: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Nach Updates suchen'),
                ),
                if (updates.status == StoreUpdateStatus.available)
                  ActionButton(
                    onPressed: scope.openUpdateStore,
                    icon: Icons.open_in_new,
                    label: 'Im Store öffnen',
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
