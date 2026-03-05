import 'dart:convert';
import 'dart:io' show File;
import 'package:http/http.dart' as http;

/// A list of results with pagination metadata.
class PagedList<T> extends Iterable<T> {
  final List<T> results;
  final int count;
  final String? next;
  final String? previous;

  PagedList(this.results, {this.count = 0, this.next, this.previous});

  @override
  Iterator<T> get iterator => results.iterator;

  int get length => results.length;
  T operator [](int index) => results[index];

  @override
  String toString() => 'PagedList(count=$count, length=$length)';
}

class BappApiClient {
  String host;
  String? tenant;
  String app;
  String? _authHeader;
  final http.Client _http;

  BappApiClient({
    String? bearer,
    String? token,
    this.host = 'https://panel.bapp.ro/api',
    this.tenant,
    this.app = 'account',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client() {
    host = host.replaceAll(RegExp(r'/+$'), '');
    if (bearer != null) _authHeader = 'Bearer $bearer';
    else if (token != null) _authHeader = 'Token $token';
  }

  Map<String, String> _buildHeaders([Map<String, String>? extra]) {
    final h = <String, String>{};
    if (_authHeader != null) h['Authorization'] = _authHeader!;
    if (tenant != null) h['x-tenant-id'] = tenant!;
    h['x-app-slug'] = app;
    if (extra != null) h.addAll(extra);
    return h;
  }

  bool _hasFiles(Object? body) {
    if (body is! Map) return false;
    return body.values.any((v) => v is File || v is http.MultipartFile || v is List<int>);
  }

  Future<dynamic> _sendMultipart(String method, Uri uri, Map body, Map<String, String> headers) async {
    final request = http.MultipartRequest(method, uri);
    request.headers.addAll(headers);
    for (final entry in body.entries) {
      final k = entry.key.toString();
      final v = entry.value;
      if (v is File) {
        request.files.add(await http.MultipartFile.fromPath(k, v.path));
      } else if (v is http.MultipartFile) {
        request.files.add(v);
      } else if (v is List<int>) {
        request.files.add(http.MultipartFile.fromBytes(k, v));
      } else {
        request.fields[k] = v.toString();
      }
    }
    final streamed = await _http.send(request);
    return await http.Response.fromStream(streamed);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? params,
    Object? body,
    Map<String, String>? headers,
  }) async {
    var uri = Uri.parse('$host$path');
    if (params != null && params.isNotEmpty) {
      uri = uri.replace(queryParameters: params);
    }

    final h = _buildHeaders(headers);
    http.Response response;

    if (body != null && _hasFiles(body)) {
      response = await _sendMultipart(method.toUpperCase(), uri, body as Map, h);
    } else {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _http.get(uri, headers: h);
        case 'POST':
          h['Content-Type'] = 'application/json';
          response = await _http.post(uri, headers: h, body: body != null ? jsonEncode(body) : null);
        case 'PUT':
          h['Content-Type'] = 'application/json';
          response = await _http.put(uri, headers: h, body: body != null ? jsonEncode(body) : null);
        case 'PATCH':
          h['Content-Type'] = 'application/json';
          response = await _http.patch(uri, headers: h, body: body != null ? jsonEncode(body) : null);
        case 'DELETE':
          response = await _http.delete(uri, headers: h);
        default:
          final request = http.Request(method.toUpperCase(), uri);
          request.headers.addAll(h);
          final streamed = await _http.send(request);
          response = await http.Response.fromStream(streamed);
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('BappApiClient: $method $path failed with ${response.statusCode}');
    }
    if (response.statusCode == 204 || response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  /// Get current user profile.
  Future<dynamic> me() =>
      _request('GET', '/tasks/bapp_framework.me', headers: {'x-app-slug': ''});

  /// Get app configuration by slug.
  Future<dynamic> getApp(String appSlug) =>
      _request('GET', '/tasks/bapp_framework.getapp', headers: {'x-app-slug': appSlug});

  /// Get entity list introspect for a content type.
  Future<dynamic> listIntrospect(String contentType) =>
      _request('GET', '/tasks/bapp_framework.listintrospect', params: {'ct': contentType});

  /// Get entity detail introspect for a content type.
  Future<dynamic> detailIntrospect(String contentType, [String? pk]) {
    final p = {'ct': contentType};
    if (pk != null) p['pk'] = pk;
    return _request('GET', '/tasks/bapp_framework.detailintrospect', params: p);
  }

  /// List entities of a content type with optional filters.
  /// Returns a [PagedList] with results, count, next, and previous.
  Future<PagedList<Map<String, dynamic>>> list(String contentType, [Map<String, String>? filters]) async {
    final data = await _request('GET', '/content-type/$contentType/', params: filters);
    final results = (data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return PagedList(
      results,
      count: data['count'] ?? 0,
      next: data['next'],
      previous: data['previous'],
    );
  }

  /// Get a single entity by content type and ID.
  Future<dynamic> get(String contentType, String id) =>
      _request('GET', '/content-type/$contentType/$id/');

  /// Create a new entity.
  Future<dynamic> create(String contentType, [Object? data]) =>
      _request('POST', '/content-type/$contentType/', body: data);

  /// Full update of an entity.
  Future<dynamic> update(String contentType, String id, [Object? data]) =>
      _request('PUT', '/content-type/$contentType/$id/', body: data);

  /// Partial update of an entity.
  Future<dynamic> patch(String contentType, String id, [Object? data]) =>
      _request('PATCH', '/content-type/$contentType/$id/', body: data);

  /// Delete an entity.
  Future<dynamic> delete(String contentType, String id) =>
      _request('DELETE', '/content-type/$contentType/$id/');

  /// List all available task codes.
  Future<dynamic> listTasks() => _request('GET', '/tasks');

  /// Get task configuration by code.
  Future<dynamic> detailTask(String code) => _request('OPTIONS', '/tasks/$code');

  /// Run a task. Uses GET when no payload, POST otherwise.
  Future<dynamic> runTask(String code, [Object? payload]) {
    if (payload == null) return _request('GET', '/tasks/$code');
    return _request('POST', '/tasks/$code', body: payload);
  }

  /// Run a long-running task and poll until finished.
  /// Returns the final task data dict which includes 'file' when
  /// the task produces a downloadable file.
  Future<dynamic> runTaskAsync(
    String code, [
    Object? payload,
    Duration pollInterval = const Duration(seconds: 1),
    Duration timeout = const Duration(minutes: 5),
  ]) async {
    final result = await runTask(code, payload);
    final taskId = result is Map ? result['id']?.toString() : null;
    if (taskId == null) return result;

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);
      final page = await list('bapp_framework.taskdata', {'id': taskId});
      if (page.isEmpty) continue;
      final taskData = page[0];
      if (taskData['failed'] == true) {
        throw Exception('Task $code failed: ${taskData['message'] ?? ''}');
      }
      if (taskData['finished'] == true) {
        return taskData;
      }
    }
    throw Exception('Task $code ($taskId) did not finish within $timeout');
  }
}
