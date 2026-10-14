import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class CapturedRequest {
  CapturedRequest(this.options, this.body);
  final RequestOptions options;
  final List<int> body;
  dynamic get json => jsonDecode(utf8.decode(body));
}

class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.respond);
  final Future<ResponseBody> Function(CapturedRequest request) respond;
  final List<CapturedRequest> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    final request = CapturedRequest(options, bytes);
    requests.add(request);
    return respond(request);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(
  Object data, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);
ResponseBody success([Map<String, dynamic> data = const {}]) =>
    jsonResponse({'type': 'success', 'status': 200, 'data': data});
