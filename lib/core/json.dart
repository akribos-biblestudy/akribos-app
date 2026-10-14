typedef Json = Map<String, dynamic>;

Json asMap(Object? value) => value is Json
    ? value
    : value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};
List<Json> asMaps(Object? value) =>
    value is List ? value.whereType<Map>().map(asMap).toList() : <Json>[];
String asString(Object? value, [String fallback = '']) =>
    value is String ? value : value?.toString() ?? fallback;
int asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse(asString(value)) ?? fallback;
