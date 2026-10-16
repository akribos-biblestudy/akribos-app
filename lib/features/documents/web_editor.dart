import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import 'web_editor_controller.dart';

/// The WebView remains on exactly one authenticated document. Links are routed
/// through the native navigation guard instead of loading foreign bridge code.
class WebEditor extends StatefulWidget {
  const WebEditor({
    super.key,
    required this.api,
    required this.controller,
    required this.readOnly,
    required this.onRetry,
    this.restore,
  });
  final AppApi api;
  final WebEditorController controller;
  final bool readOnly;
  final Json? restore;
  final VoidCallback onRetry;
  @override
  State<WebEditor> createState() => _WebEditorState();
}

class _WebEditorState extends State<WebEditor> {
  WebViewController? _view;
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      await widget.api.prepareEditorWebSession();
      if (!mounted) return;
      final scope = AppScope.of(context);
      final uri = widget.api.origin
          .resolve(
            '/app/editor/${Uri.encodeComponent(widget.controller.documentId)}',
          )
          .replace(
            queryParameters: {
              'instanceId': widget.controller.instanceId,
              'theme': Theme.of(context).brightness == Brightness.dark
                  ? 'dark'
                  : 'light',
              'fontScale':
                  '${asInt(widget.api.bootstrap['readerFontScale'], 100).clamp(70, 200)}',
              if (scope.eInk) 'eInk': '1',
            },
          );
      final background = Theme.of(context).colorScheme.surface;
      final view = WebViewController();
      _view = view;
      await view.setJavaScriptMode(JavaScriptMode.unrestricted);
      await view.setBackgroundColor(background);
      await view.addJavaScriptChannel(
        'AkribosEditor',
        onMessageReceived: (message) {
          if (mounted) widget.controller.receive(message.message);
        },
      );
      await view.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            if (request.isMainFrame &&
                target != null &&
                target.scheme == uri.scheme &&
                target.host == uri.host &&
                target.port == uri.port &&
                target.path == uri.path &&
                target.query == uri.query &&
                target.userInfo.isEmpty) {
              return NavigationDecision.navigate;
            }
            if (request.isMainFrame && target != null) {
              widget.controller.onNavigate?.call(target.toString());
            }
            return NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _fail(
                'Der Editor konnte nicht geladen werden. Bitte prüfe die Verbindung.',
              );
            }
          },
          onHttpError: (error) {
            if (error.request?.uri == uri &&
                (error.response?.statusCode ?? 200) >= 400) {
              _fail(
                'Der Editor ist nicht verfügbar (${error.response?.statusCode}).',
              );
            }
          },
        ),
      );
      widget.controller.attach(view.runJavaScript);
      if (!mounted) return;
      setState(() {});
      await view.loadRequest(uri);
      _started = true;
      await widget.controller.start(
        restore: widget.restore,
        readOnly: widget.readOnly,
      );
    } catch (error) {
      if (mounted) _fail('Der Editor konnte nicht gestartet werden: $error');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    widget.controller.fail(message);
    setState(() => _error = message);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    // Dispose removes the platform view; no session/token is passed via JS.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error =
        _error ?? (widget.controller.failed ? widget.controller.error : null);
    return Stack(
      children: [
        if (_view != null)
          Positioned.fill(child: WebViewWidget(controller: _view!)),
        if (error != null)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: widget.onRetry,
                        child: const Text('Editor erneut laden'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (error == null && (!widget.controller.initialized || !_started))
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
