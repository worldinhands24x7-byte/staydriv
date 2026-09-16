import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'network_config.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  final http.Client _client = http.Client();

  ApiClient._internal();

  Map<String, String> _addBypassHeaders(Map<String, String>? headers) {
    final Map<String, String> merged = Map<String, String>.from(NetworkConfig.standardBypassHeaders);
    if (headers != null) {
      merged.addAll(headers);
    }
    return merged;
  }

  Uri _resolveUrl(Uri originalUri) {
    final activeBase = NetworkConfig.backendUrl;
    if (originalUri.toString().startsWith('http://') || originalUri.toString().startsWith('https://')) {
      final pathAndQuery = originalUri.path + (originalUri.hasQuery ? '?${originalUri.query}' : '');
      final cleanBase = activeBase.replaceAll(RegExp(r'/+$'), '');
      return Uri.parse('$cleanBase$pathAndQuery');
    }
    final path = originalUri.toString().startsWith('/') ? originalUri.toString() : '/${originalUri.toString()}';
    return Uri.parse('${activeBase.replaceAll(RegExp(r'/+$'), '')}$path');
  }

  Future<http.Response> get(Uri url, {Map<String, String>? headers, bool retry = true, Duration timeout = const Duration(seconds: 15)}) async {
    return _callWithFailover(
      (resolvedUri) => _client.get(resolvedUri, headers: _addBypassHeaders(headers)).timeout(timeout),
      originalUrl: url,
      retry: retry,
    );
  }

  Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding, bool retry = true, Duration timeout = const Duration(seconds: 15)}) async {
    return _callWithFailover(
      (resolvedUri) => _client.post(resolvedUri, headers: _addBypassHeaders(headers), body: body, encoding: encoding).timeout(timeout),
      originalUrl: url,
      retry: retry,
    );
  }

  Future<http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding, bool retry = true, Duration timeout = const Duration(seconds: 15)}) async {
    return _callWithFailover(
      (resolvedUri) => _client.put(resolvedUri, headers: _addBypassHeaders(headers), body: body, encoding: encoding).timeout(timeout),
      originalUrl: url,
      retry: retry,
    );
  }

  Future<http.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding, bool retry = true, Duration timeout = const Duration(seconds: 15)}) async {
    return _callWithFailover(
      (resolvedUri) => _client.delete(resolvedUri, headers: _addBypassHeaders(headers), body: body, encoding: encoding).timeout(timeout),
      originalUrl: url,
      retry: retry,
    );
  }

  Future<http.Response> _callWithFailover(Future<http.Response> Function(Uri resolvedUri) requestFn, {required Uri originalUrl, bool retry = true}) async {
    int retries = retry ? 1 : 0;
    Duration delay = const Duration(milliseconds: 300);

    while (true) {
      final currentUri = _resolveUrl(originalUrl);

      try {
        final response = await requestFn(currentUri);
        final isHtmlResponse = response.body.trim().startsWith('<') || response.body.toLowerCase().contains('<html');
        if ((response.statusCode >= 500 && response.statusCode <= 599 || isHtmlResponse) && retries > 0) {
          debugPrint("ApiClient Gateway/Tunnel Error ${response.statusCode} on $currentUri. Triggering auto-discovery...");
          await NetworkConfig.autoDiscoverReachableBackend();
          retries--;
          await Future.delayed(delay);
          continue;
        }
        return response;
      } on SocketException catch (e) {
        debugPrint("ApiClient SocketException on $currentUri: $e. Auto-discovering reachable backend...");
        await NetworkConfig.autoDiscoverReachableBackend();
        if (retries <= 0) rethrow;
      } on TimeoutException catch (e) {
        debugPrint("ApiClient TimeoutException on $currentUri: $e. Auto-discovering reachable backend...");
        await NetworkConfig.autoDiscoverReachableBackend();
        if (retries <= 0) rethrow;
      } on http.ClientException catch (e) {
        debugPrint("ApiClient ClientException on $currentUri: $e. Auto-discovering reachable backend...");
        await NetworkConfig.autoDiscoverReachableBackend();
        if (retries <= 0) rethrow;
      } catch (e) {
        debugPrint("ApiClient Error on $currentUri: $e.");
        if (retries <= 0) rethrow;
      }

      retries--;
      await Future.delayed(delay);
      delay = delay * 2;
    }
  }
}
