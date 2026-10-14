import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/json.dart';
import '../../widgets/common.dart';
import '../../widgets/remote_page.dart';
import '../documents/document_widgets.dart';
import '../reader/books.dart';
import '../reader/verse_text.dart';
import 'comment_editor.dart';

String collectionReference(Json item) => referenceLabel(item);

String collectionVerseText(dynamic segments) {
  if (segments is! List) return '';
  return segments.map((segment) {
    if (segment is String) return segment;
    final value = asMap(segment);
    return switch (value['kind']) {
      'w' || 'em' => asString(value['text']),
      'wj' || 'nd' => collectionVerseText(value['children']),
      'br' => '\n',
      _ => '',
    };
  }).join();
}

class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) => RemotePage(
    path: path,
    builder: (context, data, reload) {
      final pathname = Uri.parse(path).path;
      if (pathname.startsWith('/invites/')) {
        return _Invite(path: path, data: data);
      }
      if (pathname == '/lists') return _Collections(data: data, reload: reload);
      return _CollectionDetail(
        path: path,
        data: data,
        reload: reload,
        readOnly: pathname.startsWith('/l/'),
      );
    },
  );
}

class _Collections extends StatelessWidget {
  const _Collections({required this.data, required this.reload});
  final Json data;
  final Future<void> Function() reload;

  Future<void> _create(BuildContext context) async {
    final fields = await editFeatureFields(context, 'Neue Stellensammlung', [
      const FeatureField('title', 'Titel', required: true),
    ], submit: 'Anlegen');
    if (fields != null && context.mounted) {
      await runAction(context, '/lists', 'createList', fields, reload: reload);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: reload,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        FeatureHeading(
          'Stellensammlungen',
          subtitle: 'Bibelstellen sammeln und gemeinsam besprechen.',
          actions: [
            FilledButton.icon(
              onPressed: () => _create(context),
              icon: const Icon(Icons.add),
              label: const Text('Sammlung'),
            ),
          ],
        ),
        if (asMaps(data['lists']).isEmpty)
          const EmptyFeature(
            'Deine erste Sammlung beginnt mit einer Bibelstelle.',
          ),
        for (final list in asMaps(data['lists']))
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(18),
              leading: CircleAvatar(
                child: Icon(
                  list['role'] == 'member'
                      ? Icons.group_outlined
                      : Icons.collections_bookmark_outlined,
                ),
              ),
              title: Text(asString(list['title'])),
              subtitle: Text(
                '${list['itemCount']} Stellen${list['role'] == 'member' ? ' · Gemeinsam mit ${list['ownerName']}' : ''}${list['isPublic'] == true ? ' · Mit Leselink' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => AppScope.of(context).open('/lists/${list['id']}'),
            ),
          ),
      ],
    ),
  );
}

class _Invite extends StatelessWidget {
  const _Invite({required this.path, required this.data});
  final String path;
  final Json data;

  @override
  Widget build(BuildContext context) {
    final invite = asMap(data['invite']);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const FeatureHeading('Gemeinsam studieren'),
        if (invite.isEmpty)
          const EmptyFeature(
            'Diese Einladung ist abgelaufen oder nicht mehr verfügbar.',
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.group_add_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    asString(invite['listTitle']),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    data['emailMismatch'] == true
                        ? 'Diese Einladung gehört zu einer anderen E-Mail-Adresse. Melde dich mit dem eingeladenen Konto an.'
                        : 'Du wurdest eingeladen, Bibelstellen und Kommentare in dieser Sammlung beizutragen.',
                  ),
                  const SizedBox(height: 24),
                  if (data['emailMismatch'] != true)
                    ActionButton(
                      label: 'Einladung annehmen',
                      icon: Icons.check,
                      onPressed: () async {
                        await runAction(context, path, 'default', {});
                      },
                    ),
                  if (data['emailMismatch'] == true)
                    TextButton(
                      onPressed: () => AppScope.of(context).open('/account'),
                      child: const Text('Zum Konto'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CollectionDetail extends StatelessWidget {
  const _CollectionDetail({
    required this.path,
    required this.data,
    required this.reload,
    required this.readOnly,
  });
  final String path;
  final Json data;
  final Future<void> Function() reload;
  final bool readOnly;
  bool get owner => data['isOwner'] == true;

  Future<void> _form(
    BuildContext context,
    String title,
    String action,
    List<FeatureField> fields, {
    Json extra = const {},
  }) async {
    final values = await editFeatureFields(context, title, fields);
    if (values != null && context.mounted) {
      await runAction(context, path, action, {
        ...extra,
        ...values,
      }, reload: reload);
    }
  }

  Future<void> _comment(
    BuildContext context,
    Json item, {
    Json? parent,
    Json? existing,
  }) async {
    final saved = await editCollectionComment(
      context,
      path: path,
      originalHtml: existing == null ? null : asString(existing['bodyHtml']),
      reply: parent != null,
      fields: {
        'itemId': item['id'],
        'parentCommentId': existing?['parentCommentId'] ?? parent?['id'] ?? '',
        if (existing != null) 'commentId': existing['id'],
      },
    );
    if (saved) await reload();
  }

  Widget _commentNode(
    BuildContext context,
    Json item,
    Json comment, {
    int depth = 0,
  }) {
    final own = comment['authorUserId'] == data['currentUserId'];
    return Padding(
      padding: EdgeInsets.only(left: depth > 0 && depth < 4 ? 14 : 0, top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      asString(comment['authorName']),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  Text(
                    shortDate(comment['createdAt']),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (!readOnly && (own || owner))
                    PopupMenuButton<String>(
                      tooltip: 'Kommentaraktionen',
                      onSelected: (action) async {
                        if (action == 'edit') {
                          await _comment(context, item, existing: comment);
                        } else if (await confirmAction(
                          context,
                          'Kommentar entfernen?',
                        )) {
                          if (!context.mounted) return;
                          await runAction(context, path, 'deleteComment', {
                            'commentId': comment['id'],
                          }, reload: reload);
                        }
                      },
                      itemBuilder: (_) => [
                        if (own)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Bearbeiten'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Entfernen'),
                        ),
                      ],
                    ),
                ],
              ),
              HtmlContent(html: asString(comment['bodyHtml'])),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final reaction in asMaps(comment['reactions']))
                    ActionChip(
                      label: Text('${reaction['emoji']} ${reaction['count']}'),
                      backgroundColor: reaction['reactedByMe'] == true
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : null,
                      onPressed: readOnly
                          ? null
                          : () => runAction(context, path, 'react', {
                              'commentId': comment['id'],
                              'emoji': reaction['emoji'],
                            }, reload: reload),
                    ),
                  if (!readOnly) ...[
                    PopupMenuButton<String>(
                      tooltip: 'Reagieren',
                      onSelected: (emoji) => runAction(context, path, 'react', {
                        'commentId': comment['id'],
                        'emoji': emoji,
                      }, reload: reload),
                      itemBuilder: (_) => [
                        for (final emoji in [
                          '👍',
                          '👎',
                          '😄',
                          '🎉',
                          '😕',
                          '❤️',
                          '🚀',
                          '👀',
                        ])
                          PopupMenuItem(value: emoji, child: Text(emoji)),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.add_reaction_outlined, size: 20),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _comment(context, item, parent: comment),
                      child: const Text('Antworten'),
                    ),
                  ],
                ],
              ),
              for (final reply in asMaps(comment['replies']))
                _commentNode(context, item, reply, depth: depth + 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _members(BuildContext context) => Card(
    child: ExpansionTile(
      title: const Text('Gemeinsam bearbeiten'),
      leading: const Icon(Icons.group_outlined),
      children: [
        for (final member in asMaps(data['members']))
          ListTile(
            leading: Icon(
              member['kind'] == 'pending'
                  ? Icons.mark_email_unread_outlined
                  : Icons.person_outline,
            ),
            title: Text(asString(member['name'], asString(member['email']))),
            subtitle: Text(
              member['kind'] == 'pending' ? 'Einladung ausstehend' : 'Mitglied',
            ),
            trailing: !owner
                ? null
                : IconButton(
                    tooltip: member['kind'] == 'pending'
                        ? 'Einladung widerrufen'
                        : 'Mitglied entfernen',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () async {
                      if (!await confirmAction(
                        context,
                        member['kind'] == 'pending'
                            ? 'Einladung widerrufen?'
                            : 'Mitglied entfernen?',
                      )) {
                        return;
                      }
                      if (!context.mounted) return;
                      await runAction(
                        context,
                        path,
                        member['kind'] == 'pending'
                            ? 'revokeInvite'
                            : 'removeMember',
                        {
                          member['kind'] == 'pending' ? 'inviteId' : 'memberId':
                              member['id'],
                        },
                        reload: reload,
                      );
                    },
                  ),
          ),
        if (owner)
          TextButton.icon(
            onPressed: () => _form(
              context,
              'Zur Zusammenarbeit einladen',
              'inviteMember',
              [const FeatureField('email', 'E-Mail-Adresse', required: true)],
            ),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Person einladen'),
          ),
        if (!owner)
          TextButton(
            onPressed: () async {
              if (!await confirmAction(context, 'Sammlung verlassen?')) return;
              if (!context.mounted) return;
              await runAction(context, path, 'leaveList', {});
            },
            child: const Text('Sammlung verlassen'),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final list = asMap(data['list']);
    final items = asMaps(data['items']);
    final comments = asMap(data['comments']);
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          FeatureHeading(
            asString(list['title']),
            subtitle: readOnly
                ? 'Geteilte Stellensammlung · Leseansicht'
                : '${items.length} Bibelstellen',
            actions: [
              if (!readOnly)
                FilledButton.icon(
                  onPressed: () =>
                      _form(context, 'Bibelstelle hinzufügen', 'addVerse', [
                        const FeatureField(
                          'reference',
                          'Bibelstelle, z. B. Joh 3,16',
                          required: true,
                        ),
                      ]),
                  icon: const Icon(Icons.add),
                  label: const Text('Bibelstelle'),
                ),
              if (owner)
                PopupMenuButton<String>(
                  tooltip: 'Sammlung verwalten',
                  onSelected: (action) async {
                    if (action == 'rename') {
                      await _form(context, 'Sammlung umbenennen', 'rename', [
                        FeatureField(
                          'title',
                          'Titel',
                          value: asString(list['title']),
                          required: true,
                        ),
                      ]);
                    } else if (action == 'copy') {
                      await Clipboard.setData(
                        ClipboardData(
                          text: AppScope.of(context).api.origin
                              .resolve('/l/${list['slug']}')
                              .toString(),
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Leselink kopiert.')),
                        );
                      }
                    } else if (action == 'share') {
                      await runAction(context, path, 'share', {
                        'isPublic': list['isPublic'] == true ? 'false' : 'true',
                      }, reload: reload);
                    } else if (await confirmAction(
                      context,
                      'Sammlung und alle ihre Kommentare löschen?',
                    )) {
                      if (!context.mounted) return;
                      await runAction(context, path, 'delete', {});
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Text('Umbenennen'),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Text(
                        list['isPublic'] == true
                            ? 'Leselink deaktivieren'
                            : 'Leselink freigeben',
                      ),
                    ),
                    if (list['isPublic'] == true)
                      const PopupMenuItem(
                        value: 'copy',
                        child: Text('Leselink kopieren'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Sammlung löschen'),
                    ),
                  ],
                ),
            ],
          ),
          if (asString(list['introHtml']).isNotEmpty)
            HtmlContent(html: asString(list['introHtml'])),
          if (!readOnly) _members(context),
          if (items.isEmpty)
            const EmptyFeature('Füge die erste Bibelstelle hinzu.'),
          for (final item in items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () => AppScope.of(context).open(
                              '/${Uri.encodeComponent(collectionReference(item))}',
                            ),
                            icon: const Icon(Icons.menu_book),
                            label: Text(collectionReference(item)),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Vers kopieren',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text:
                                    '${collectionReference(item)}\n${collectionVerseText(item['segments'])}',
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Vers kopiert.')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_outlined),
                        ),
                        if (!readOnly && item['canDelete'] == true)
                          IconButton(
                            tooltip: 'Stelle entfernen',
                            onPressed: () async {
                              if (!await confirmAction(
                                context,
                                'Bibelstelle aus der Sammlung entfernen?',
                              )) {
                                return;
                              }
                              if (!context.mounted) return;
                              await runAction(context, path, 'removeVerse', {
                                'reference': collectionReference(item),
                              }, reload: reload);
                            },
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                    if (item['segments'] == null)
                      const Text(
                        'Für diese Stelle ist aktuell kein Bibeltext verfügbar.',
                      )
                    else
                      VerseText(
                        segments: item['segments'] as List,
                        onWord: (word, position) =>
                            AppScope.of(context).open('/${word['strong']}'),
                      ),
                    if (asString(item['addedByName']).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Hinzugefügt von ${item['addedByName']}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    for (final comment in asMaps(
                      comments[asString(item['id'])],
                    ))
                      _commentNode(context, item, comment),
                    if (!readOnly)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextButton.icon(
                          onPressed: () => _comment(context, item),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Kommentieren'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
