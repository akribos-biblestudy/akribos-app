import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/app_scope.dart';

/// The account's reading size applies to content, independently of UI labels.
/// TextScaler remains Flutter's responsibility so accessibility scaling is added once.
TextStyle readingTextStyle(BuildContext context, {double? fontScale}) =>
    TextStyle(
      fontFamily: 'AkribosText',
      fontFamilyFallback: const ['NotoSansHebrew'],
      fontSize:
          19 *
          (fontScale ??
                  asInt(
                        AppScope.of(context).api.bootstrap['readerFontScale'],
                        100,
                      ) /
                      100)
              .clamp(.7, 2),
      height: 1.65,
    );

class HtmlContent extends StatelessWidget {
  const HtmlContent({
    super.key,
    required this.html,
    this.onTapUrl,
    this.textStyle,
    this.customStylesBuilder,
    this.customWidgetBuilder,
    this.scalableListMarkers = false,
  });
  final String html;
  final FutureOr<bool> Function(String)? onTapUrl;
  final TextStyle? textStyle;
  final CustomStylesBuilder? customStylesBuilder;
  final CustomWidgetBuilder? customWidgetBuilder;
  final bool scalableListMarkers;
  @override
  Widget build(BuildContext context) => HtmlWidget(
    html,
    textStyle: textStyle,
    customStylesBuilder: customStylesBuilder,
    customWidgetBuilder: customWidgetBuilder,
    baseUrl: AppScope.of(context).api.origin,
    factoryBuilder: () => _PrivateHtmlFactory(
      AppScope.of(context).api,
      scalableListMarkers: scalableListMarkers,
      eInk: AppScope.of(context).eInk,
    ),
    onTapUrl:
        onTapUrl ??
        (url) async {
          final scope = AppScope.of(context);
          final parsed = Uri.tryParse(url);
          if (parsed == null) return false;
          final uri = scope.api.origin.resolveUri(parsed);
          if (!['https', 'http', 'mailto'].contains(uri.scheme) ||
              uri.userInfo.isNotEmpty) {
            return false;
          }
          // Let HtmlWidget resolve same-document anchors inside its own scroll
          // view. Reporting them as handled would instead leave this document.
          if (parsed.hasFragment &&
              ((!parsed.hasScheme &&
                      parsed.host.isEmpty &&
                      parsed.path.isEmpty &&
                      !parsed.hasQuery) ||
                  uri.removeFragment() == scope.api.origin)) {
            return false;
          }
          if (uri.scheme != 'mailto' && uri.origin == scope.api.origin.origin) {
            await scope.open(
              '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}'
              '${uri.hasFragment ? '#${uri.fragment}' : ''}',
            );
            return true;
          }
          if (!await confirmAction(
            context,
            'Externen Link öffnen?',
            uri.toString(),
          )) {
            return true;
          }
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return true;
        },
  );
}

/// HTML may describe images, but only the authenticated first-party transport loads them.
/// Disable built-in network/file providers as they also serve CSS background images.
class _PrivateHtmlFactory extends WidgetFactory {
  _PrivateHtmlFactory(
    this.api, {
    this.scalableListMarkers = false,
    this.eInk = false,
  });
  final AppApi api;
  final bool scalableListMarkers, eInk;

  @override
  Future<bool> onTapAnchor(String id, EnsureVisible scrollTo) => scrollTo(
    id,
    duration: eInk ? Duration.zero : const Duration(milliseconds: 100),
  );

  @override
  Widget? buildListMarker(
    BuildTree tree,
    InheritedProperties resolved,
    String listStyleType,
    int index,
  ) {
    if (!scalableListMarkers || listStyleType == 'none') {
      return super.buildListMarker(tree, resolved, listStyleType, index);
    }
    final marker = switch (listStyleType) {
      'disc' => '•',
      'circle' => '◦',
      'square' => '▪',
      _ => getListMarkerText(listStyleType, index),
    };
    final style = resolved.prepareTextStyle();
    final child = buildText(
      tree,
      resolved,
      TextSpan(text: marker, style: style),
    );
    if (child == null) return null;
    return Builder(
      builder: (context) => Padding(
        padding: EdgeInsetsDirectional.only(
          end:
              MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14) *
              .15,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget? buildImage(BuildTree tree, ImageMetadata data) {
    final source = data.sources.firstOrNull;
    if (source == null) return null;
    return _PrivateHtmlImage(
      api: api,
      source: source.url,
      label: data.alt ?? data.title ?? 'Abbildung',
    );
  }

  @override
  ImageProvider? imageProviderFromNetwork(String url) => null;
  @override
  ImageProvider? imageProviderFromFileUri(String url) => null;
  @override
  ImageProvider? imageProviderFromDataUri(String url) => null;
  @override
  ImageProvider? imageProviderFromAsset(String url) => null;
}

class _PrivateHtmlImage extends StatefulWidget {
  const _PrivateHtmlImage({
    required this.api,
    required this.source,
    required this.label,
  });
  final AppApi api;
  final String source, label;
  @override
  State<_PrivateHtmlImage> createState() => _PrivateHtmlImageState();
}

class _PrivateHtmlImageState extends State<_PrivateHtmlImage> {
  Future<Uint8List>? _image;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PrivateHtmlImage old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api || old.source != widget.source) _load();
  }

  void _load() {
    try {
      widget.api.safeUri(widget.source);
      _image = widget.api.bytes(widget.source);
    } on ApiException {
      _image = null;
    }
  }

  Widget _placeholder(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        const Icon(Icons.image_outlined),
        const SizedBox(width: 8),
        Expanded(child: Text('${widget.label} · $message')),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => _image == null
      ? _placeholder('Externes Bild wird nicht geladen')
      : FutureBuilder<Uint8List>(
          future: _image,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _placeholder('Bild nicht verfügbar');
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Image.memory(
              snapshot.data!,
              semanticLabel: widget.label,
              fit: BoxFit.contain,
              errorBuilder: (_, error, stack) =>
                  _placeholder('Bild nicht verfügbar'),
            );
          },
        );
}

class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tonal = false,
  });
  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool tonal;
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _busy = false;
  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: _busy || widget.onPressed == null ? null : _run,
    icon: _busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon ?? Icons.check),
    label: Text(widget.label),
  );
}

void showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        duration: const Duration(seconds: 8),
        showCloseIcon: true,
      ),
    );

Future<bool> confirmAction(
  BuildContext context,
  String title, [
  String? message,
]) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bestätigen'),
          ),
        ],
      ),
    ) ??
    false;

Future<ApiResult?> runAction(
  BuildContext context,
  String path,
  String action,
  Json fields, {
  Future<void> Function()? reload,
}) async {
  try {
    final scope = AppScope.of(context);
    final result = await scope.api.action(path, action, fields);
    if (!context.mounted) return result;
    if (result.isRedirect) {
      await scope.open(result.location!);
    } else if (!result.isSuccess) {
      showError(context, result.message);
    } else {
      if (reload != null) await reload();
    }
    return result;
  } catch (error) {
    if (context.mounted) showError(context, error);
    return null;
  }
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1100});
  final List<Widget> children;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}
