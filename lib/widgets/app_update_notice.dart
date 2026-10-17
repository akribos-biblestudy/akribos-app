import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import 'common.dart';

/// A dismissible in-app notice, with no modal dialog or notification permission.
class AppUpdateNotice extends StatelessWidget {
  const AppUpdateNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final updates = scope.updates;
    if (updates == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        if (!updates.showNotice) return const SizedBox.shrink();
        final colors = Theme.of(context).colorScheme;
        return Material(
          color: scope.eInk ? Colors.white : colors.surfaceContainerLow,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: scope.eInk ? Colors.black : colors.outlineVariant,
                  width: scope.eInk ? 2 : 1,
                ),
              ),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    // The notice must not consume the reading viewport in
                    // landscape or at a large accessibility text size.
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .3,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              updates.update?.version == null
                                  ? 'Update verfügbar'
                                  : 'Update auf ${updates.update!.version} verfügbar',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ActionButton(
                            onPressed: scope.openUpdateStore,
                            icon: Icons.open_in_new,
                            label: 'Im Store öffnen',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Update-Hinweis für 24 Stunden schließen',
                  onPressed: updates.dismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
