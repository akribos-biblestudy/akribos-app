import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_scope.dart';

class RemotePage extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.path,
    required this.builder,
    this.embedded = false,
  });
  final bool embedded;
  final String path;
  final Widget Function(
    BuildContext context,
    Json data,
    Future<void> Function() reload,
  )
  builder;
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  Json? _data;
  Object? _error;
  AppApi? _api;
  int _generation = 0;
  bool _loading = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppScope.of(context).api;
    if (_api != api) {
      _api = api;
      _data = null;
      _load();
    }
  }

  @override
  void didUpdateWidget(RemotePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _data = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api!.page(widget.path);
      if (mounted && generation == _generation) setState(() => _data = data);
    } on AppRedirect catch (redirect) {
      if (mounted && generation == _generation) {
        setState(() => _data = null);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) {
            AppScope.of(context).open(redirect.location);
          }
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          if (error is ApiException && [401, 403, 404].contains(error.status)) {
            _data = null;
          }
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(_error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Erneut versuchen'),
                ),
              ],
            ),
          ),
        if (_data != null)
          if (widget.embedded)
            widget.builder(context, _data!, _load)
          else
            Expanded(child: widget.builder(context, _data!, _load)),
      ],
    );
  }
}
