import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/app_scope.dart';
import 'common.dart';

enum FieldKind {
  text,
  multiline,
  password,
  email,
  number,
  toggle,
  select,
  multi,
  file,
  color,
}

class FormFieldSpec {
  const FormFieldSpec(
    this.name,
    this.label, {
    this.value = '',
    this.kind = FieldKind.text,
    this.options = const {},
    this.required = false,
    this.hint,
  });
  final String name, label;
  final Object? value;
  final FieldKind kind;
  final Map<String, String> options;
  final bool required;
  final String? hint;
}

/// Shared native controls; each screen explicitly declares its business fields and action.
class ActionForm extends StatefulWidget {
  const ActionForm({
    super.key,
    required this.title,
    required this.path,
    required this.action,
    required this.fields,
    this.hidden = const {},
    this.submitLabel = 'Speichern',
    this.reload,
    this.onResult,
    this.confirmation,
  });
  final String title, path, action, submitLabel;
  final List<FormFieldSpec> fields;
  final Json hidden;
  final Future<void> Function()? reload;
  final Future<void> Function(ApiResult result)? onResult;
  final String? confirmation;
  @override
  State<ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<ActionForm> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _text = {};
  final Json _values = {};
  final Map<String, AppUpload> _files = {};
  ApiResult? _result;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _syncFields();
  }

  @override
  void didUpdateWidget(ActionForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.path != widget.path || oldWidget.action != widget.action;
    if (changed) {
      for (final controller in _text.values) {
        controller.dispose();
      }
      _text.clear();
      _values.clear();
      _files.clear();
      _result = null;
    }
    _syncFields(changed ? null : oldWidget);
  }

  void _syncFields([ActionForm? previous]) {
    final names = widget.fields.map((field) => field.name).toSet();
    for (final name
        in _text.keys.where((name) => !names.contains(name)).toList()) {
      _text.remove(name)?.dispose();
    }
    for (final field in widget.fields) {
      final old = previous?.fields
          .where((candidate) => candidate.name == field.name)
          .firstOrNull;
      final saved = _result?.isSuccess == true;
      if ([
        FieldKind.toggle,
        FieldKind.select,
        FieldKind.multi,
        FieldKind.file,
      ].contains(field.kind)) {
        final untouched = field.kind == FieldKind.multi
            ? listEquals(
                _values[field.name] is List ? _values[field.name] as List : [],
                old?.value is List ? old!.value as List : [],
              )
            : _values[field.name] == old?.value;
        if (old == null || untouched || saved) {
          _values[field.name] = field.kind == FieldKind.multi
              ? List<String>.from(
                  field.value is List ? field.value as List : [],
                )
              : field.value;
        }
      } else {
        final controller = _text[field.name];
        if (controller == null) {
          _text[field.name] = TextEditingController(
            text: asString(field.value),
          );
        } else if (saved || controller.text == asString(old?.value)) {
          controller.text = asString(field.value);
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final scope = AppScope.of(context);
    if (widget.confirmation != null &&
        !await confirmAction(context, widget.title, widget.confirmation!)) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final fields = <String, dynamic>{...widget.hidden};
      for (final field in widget.fields) {
        if (field.kind == FieldKind.file) continue;
        if (field.kind == FieldKind.toggle) {
          if (_values[field.name] == true || _values[field.name] == 'on') {
            fields[field.name] = 'on';
          }
        } else {
          fields[field.name] =
              _text[field.name]?.text ?? _values[field.name] ?? '';
          if (field.kind == FieldKind.color) {
            fields[field.name] = asString(fields[field.name]).trim();
          }
        }
      }
      final result = _files.isEmpty
          ? await scope.api.action(widget.path, widget.action, fields)
          : await scope.api.uploadAction(
              widget.path,
              widget.action,
              fields,
              _files.values.toList(),
            );
      if (!mounted) return;
      setState(() => _result = result);
      if (widget.onResult != null) {
        await widget.onResult!(result);
      } else if (result.isRedirect) {
        await scope.open(result.location!);
      } else if (result.isSuccess) {
        // A one-time token remains visible until the user leaves this form.
        if (widget.reload != null) await widget.reload!();
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    title: widget.title,
    children: [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final field in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _field(field),
              ),
            if (_result != null && !_result!.isRedirect)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _result!.isSuccess ? 'Gespeichert.' : _result!.message,
                  style: TextStyle(
                    color: _result!.isSuccess
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (_result?.data['createdApiKey'] != null)
              _secret(asString(asMap(_result!.data['createdApiKey'])['key'])),
            for (final key in ['resetLink', 'verifyLink'])
              if (_result?.data[key] != null)
                _secret(asString(_result!.data[key])),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(widget.submitLabel),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _secret(String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Bitte sicher aufbewahren:'),
      SelectableText(value),
      TextButton.icon(
        onPressed: () => Clipboard.setData(ClipboardData(text: value)),
        icon: const Icon(Icons.copy),
        label: const Text('Kopieren'),
      ),
    ],
  );
  Widget _field(FormFieldSpec field) {
    switch (field.kind) {
      case FieldKind.color:
        final controller = _text[field.name]!;
        final hex = controller.text.trim();
        final valid = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: controller,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: field.label,
                helperText: field.hint ?? 'Eigene Farbe im Format #RRGGBB',
                prefixIcon: Icon(
                  valid ? Icons.circle : Icons.palette_outlined,
                  key: ValueKey('color-preview:${field.name}'),
                  color: valid
                      ? Color(
                          int.parse(hex.substring(1), radix: 16) | 0xff000000,
                        )
                      : null,
                  semanticLabel: valid
                      ? 'Farbvorschau $hex'
                      : 'Ungültige Farbe',
                ),
              ),
              validator: (value) =>
                  RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch((value ?? '').trim())
                  ? null
                  : 'Bitte eine Farbe im Format #RRGGBB eingeben.',
              onChanged: (_) => setState(() => _result = null),
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in field.options.entries)
                  ChoiceChip(
                    label: Text(option.value),
                    avatar: Icon(
                      Icons.circle,
                      color: Color(
                        int.parse(option.key.substring(1), radix: 16) |
                            0xff000000,
                      ),
                    ),
                    selected: hex.toLowerCase() == option.key.toLowerCase(),
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            controller.text = option.key;
                            _result = null;
                          }),
                  ),
              ],
            ),
          ],
        );
      case FieldKind.toggle:
        return SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          subtitle: field.hint == null ? null : Text(field.hint!),
          value: _values[field.name] == true || _values[field.name] == 'on',
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _result = null;
                  _values[field.name] = value;
                }),
        );
      case FieldKind.select:
        return DropdownButtonFormField<String>(
          key: ValueKey('${field.name}:${_values[field.name]}'),
          initialValue: field.options.containsKey(asString(_values[field.name]))
              ? asString(_values[field.name])
              : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: field.label,
            helperText: field.hint,
          ),
          items: field.options.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _result = null;
                  _values[field.name] = value;
                }),
          validator: (value) =>
              field.required && (value == null || value.isEmpty)
              ? 'Bitte auswählen.'
              : null,
        );
      case FieldKind.multi:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label),
            for (final option in field.options.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(option.value),
                value: (_values[field.name] as List).contains(option.key),
                onChanged: _busy
                    ? null
                    : (checked) => setState(() {
                        _result = null;
                        final selected = _values[field.name] as List;
                        if (checked == true) {
                          selected.add(option.key);
                        } else {
                          selected.remove(option.key);
                        }
                      }),
              ),
          ],
        );
      case FieldKind.file:
        return FormField<AppUpload>(
          validator: (_) => field.required && !_files.containsKey(field.name)
              ? 'Bitte eine Datei auswählen.'
              : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          final file = await FilePicker.pickFile();
                          if (file == null || !mounted) return;
                          final length = await file.length();
                          if (length != null && length > 64 * 1024 * 1024) {
                            throw const ApiException(
                              'Die ausgewählte Datei ist zu groß.',
                              status: 413,
                            );
                          }
                          final bytes = await file.readAsBytes();
                          if (!mounted) return;
                          setState(
                            () => _files[field.name] = AppUpload(
                              field: field.name,
                              name: file.name,
                              bytes: bytes,
                            ),
                          );
                          state.didChange(_files[field.name]);
                        } catch (error) {
                          if (mounted) showError(context, error);
                        }
                      },
                icon: const Icon(Icons.attach_file),
                label: Text(_files[field.name]?.name ?? field.label),
              ),
              if (state.hasError)
                Text(
                  state.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        );
      default:
        return TextFormField(
          controller: _text[field.name],
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: field.label,
            helperText: field.hint,
          ),
          obscureText: field.kind == FieldKind.password,
          autocorrect: field.kind != FieldKind.password,
          enableSuggestions: field.kind != FieldKind.password,
          onChanged: (_) {
            if (_result != null) setState(() => _result = null);
          },
          maxLines: field.kind == FieldKind.multiline ? 5 : 1,
          keyboardType: switch (field.kind) {
            FieldKind.email => TextInputType.emailAddress,
            FieldKind.number => TextInputType.number,
            FieldKind.multiline => TextInputType.multiline,
            _ => TextInputType.text,
          },
          validator: (value) => field.required && (value ?? '').trim().isEmpty
              ? 'Bitte ausfüllen.'
              : null,
          onFieldSubmitted: field.kind == FieldKind.multiline
              ? null
              : (_) => _submit(),
        );
    }
  }
}
