import 'dart:async';

import 'package:http/http.dart' as http;

/// Fetches the state and version endpoints, in parallel.
class InquisitorClient {
  /// Creates a client.
  ///
  /// A [client] passed in is *not* closed by [close], since its lifetime
  /// belongs to the caller.
  InquisitorClient({
    required this.stateUrl,
    required this.versionUrl,
    this.headers = const <String, String>{},
    this.timeout = const Duration(seconds: 10),
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// The state endpoint.
  final Uri stateUrl;

  /// The version endpoint.
  final Uri versionUrl;

  /// Extra request headers, for example an API key.
  final Map<String, String> headers;

  /// How long to wait for each request before giving up.
  final Duration timeout;

  final http.Client _client;
  final bool _ownsClient;

  /// Fetches both endpoints and returns their raw bodies. Throws when either
  /// request fails.
  Future<({String state, String version})> fetch() async {
    final bodies = await Future.wait(<Future<String>>[
      _get(stateUrl),
      _get(versionUrl),
    ]);
    return (state: bodies[0], version: bodies[1]);
  }

  Future<String> _get(Uri uri) async {
    final response = await _client.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Inquisitor request failed with HTTP ${response.statusCode}',
        uri,
      );
    }
    return response.body;
  }

  /// Releases the HTTP client, if this instance created it.
  void close() {
    if (_ownsClient) _client.close();
  }
}
