import 'package:flutter/material.dart';

import '../../core/json.dart';

const sermonFormats = <String, String>{
  'sermon': 'Predigt',
  'home-group': 'Hauskreis',
  'bible-study': 'Bibelstunde',
  'youth': 'Jugendstunde',
  'children': 'Kinderstunde',
  'other': 'Sonstiges',
};

class FeatureField {
  const FeatureField(
    this.name,
    this.label, {
    this.value = '',
    this.options,
    this.lines = 1,
    this.required = false,
  });
  final String name;
  final String label;
  final String value;
  final Map<String, String>? options;
  final int lines;
  final bool required;
}

Future<Json?> editFeatureFields(
  BuildContext context,
  String title,
  List<FeatureField> fields, {
  String submit = 'Speichern',
  Future<void> Function(Json fields)? onSubmit,
}) async {
  final controllers = {
    for (final field in fields)
      field.name: TextEditingController(
        text: field.options != null && !field.options!.containsKey(field.value)
            ? field.options!.keys.first
            : field.value,
      ),
  };
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  try {
    final route = DialogRoute<Json>(
      context: context,
      barrierDismissible: onSubmit == null,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final field in fields)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: field.options == null
                              ? TextFormField(
                                  controller: controllers[field.name],
                                  enabled: !busy,
                                  maxLines: field.lines,
                                  decoration: InputDecoration(
                                    labelText: field.label,
                                  ),
                                  validator: (value) =>
                                      field.required &&
                                          (value == null ||
                                              value.trim().isEmpty)
                                      ? 'Bitte ausfüllen.'
                                      : null,
                                )
                              : DropdownButtonFormField<String>(
                                  initialValue:
                                      field.options!.containsKey(field.value)
                                      ? field.value
                                      : field.options!.keys.first,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: field.label,
                                  ),
                                  items: [
                                    for (final option in field.options!.entries)
                                      DropdownMenuItem(
                                        value: option.key,
                                        child: Text(
                                          option.value,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: busy
                                      ? null
                                      : (value) =>
                                            controllers[field.name]!.text =
                                                value ?? '',
                                ),
                        ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        final values = <String, dynamic>{
                          for (final field in fields)
                            field.name: controllers[field.name]!.text,
                        };
                        if (onSubmit != null) {
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await onSubmit(values);
                          } catch (failure) {
                            if (context.mounted) {
                              setState(() {
                                busy = false;
                                error = '$failure';
                              });
                            }
                            return;
                          }
                        }
                        if (context.mounted) Navigator.pop(context, values);
                      },
                child: Text(busy ? 'Speichert …' : submit),
              ),
            ],
          ),
        ),
      ),
    );
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    return result;
  } finally {
    // Wait for the reverse transition above before disposing dialog-owned fields.
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }
}

class FeatureHeading extends StatelessWidget {
  const FeatureHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      spacing: 20,
      runSpacing: 16,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    ),
  );
}

class EmptyFeature extends StatelessWidget {
  const EmptyFeature(
    this.message, {
    super.key,
    this.icon = Icons.auto_stories_outlined,
  });
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
    child: Column(
      children: [
        Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

String shortDate(dynamic value) {
  final parsed = DateTime.tryParse(asString(value));
  if (parsed == null) return '';
  return '${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year}';
}

String calendarDate(dynamic value) {
  final parsed = DateTime.tryParse(asString(value));
  return parsed?.toIso8601String().substring(0, 10) ?? '';
}

Map<String, String> itemOptions(
  dynamic rows, {
  String label = 'title',
  String? empty,
}) => {
  '': ?empty,
  for (final item in asMaps(rows)) asString(item['id']): asString(item[label]),
};
