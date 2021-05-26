import 'dart:convert';
import 'dart:io';

import '../cache/caches.dart';
import 'server.dart';
import 'package:serverpod/src/authentication/scope.dart';
import '../generated/protocol.dart';
import '../database/database.dart';

/// Defines the type of a [Session].
enum SessionType {
  /// The [Session] is a [Endpoint] method call.
  methodCall,

  /// The [Session] is a [FutureCall].
  futureCall,
}

/// When a call is made to the [Server] a [Session] object is created. It
/// contains all data associated with the current connection and provides
/// easy access to the database.
class Session {
  /// The type of session, depending on if it's created for a method call
  /// or a future call.
  final SessionType type;

  /// The [Server] that created the session.
  final Server server;

  /// Max lifetime of the session, after it will be forcefully terminated.
  final Duration maxLifeTime;

  late DateTime _startTime;
  /// The time the session object was created.
  DateTime get startTime => _startTime;

  /// Queries performed during the session.
  final List<QueryLogEntry> queries = [];

  /// Log messages saved during the session.
  final List<LogEntry> logs = [];

  int? _authenticatedUser;
  Set<Scope>? _scopes;

  /// Access to the database.
  late final Database db;

  MethodCallInfo? _methodCall;
  /// Info about the current method call, only valid if the type is
  /// [SessionType.methodCall], otherwise null.
  MethodCallInfo? get methodCall => _methodCall;

  FutureCallInfo? _futureCall;
  /// Info about the current future call, only valid if the type is
  /// [SessionType.futureCall], otherwise null.
  FutureCallInfo? get futureCall => _futureCall;

  String? _authenticationKey;
  /// The authentication key passed from the client.
  String? get authenticationKey => _authenticationKey;

  /// Provides access to all caches used by the server.
  Caches get caches => server.caches;

  /// Map of passwords loaded from config/passwords.yaml
  Map<String, String> get passwords => server.passwords;

  /// Creates a new session. This is typically done internally by the [Server].
  Session({
    this.type = SessionType.methodCall,
    required this.server,
    Uri? uri,
    String? body,
    String? endpointName,
    String? authenticationKey,
    this.maxLifeTime=const Duration(minutes: 1),
    HttpRequest? httpRequest,
    String? futureCallName,
  }){
    _startTime = DateTime.now();

    if (type == SessionType.methodCall) {
      // Method call session

      // Read query parameters
      var queryParameters = <String, String>{};
      if (body != null && body != '' && body != 'null') {
        queryParameters = jsonDecode(body).cast<String, String>();
      }

      // Get the the authentication key, if any
      authenticationKey ??= queryParameters['auth'];
      _authenticationKey = authenticationKey;

      var methodName = queryParameters['method'];
      if (methodName == null && endpointName == 'webserver')
        methodName = '';

      db = Database(session: this);

      _methodCall = MethodCallInfo(
        uri: uri!,
        body: body!,
        queryParameters: queryParameters,
        endpointName: endpointName!,
        methodName: methodName!,
        httpRequest: httpRequest!,
      );
    }
    else if (type == SessionType.futureCall){
      // Future call session

      _futureCall = FutureCallInfo(
        callName: futureCallName!,
      );
    }
  }

  bool _initialized = false;

  Future<void> _initialize() async {
    if (server.authenticationHandler != null  && _authenticationKey != null) {
      var authenticationInfo = await server.authenticationHandler!(this, _authenticationKey!);
      _scopes = authenticationInfo?.scopes;
      _authenticatedUser = authenticationInfo?.authenticatedUserId;
    }
    _initialized = true;
  }

  /// Returns the id of an authenticated user or null if the user isn't signed
  /// in.
  Future<int?> get authenticatedUserId async {
    if (!_initialized)
      await _initialize();
    return _authenticatedUser;
  }

  /// Returns the scopes associated with an authenticated user.
  Future<Set<Scope>?> get scopes async {
    if (!_initialized)
      await _initialize();
    return _scopes;
  }

  /// Returns true if the user is signed in.
  Future<bool> get isUserSignedIn async {
    return (await authenticatedUserId) != null;
  }

  /// Returns the duration this session has been open.
  Duration get duration => DateTime.now().difference(_startTime);

  /// Closes the session.
  Future<void> close() async {
  }

  /// Logs a message. Default [LogLevel] is [LogLevel.info]. The log is written
  /// to the database when the session is closed.
  void log(String message, {LogLevel? level, dynamic? exception, StackTrace? stackTrace}) {
    logs.add(
      LogEntry(
        serverId: server.serverId,
        logLevel: (level ?? LogLevel.info).index,
        message: message,
        time: DateTime.now(),
        exception: exception != null ? '$exception' : null,
        stackTrace: stackTrace != null ? '$stackTrace' : null,
      ),
    );
  }
}

/// Information associated with a method call.
class MethodCallInfo {
  /// The uri that was used to call the server.
  final Uri uri;

  /// The body of the server call.
  final String body;

  /// Query parameters of the server call.
  final Map<String, String> queryParameters;

  /// The name of the called [Endpoint].
  final String endpointName;

  /// The name of the method that is being called.
  final String methodName;

  /// The [HttpRequest] associated with the call.
  final HttpRequest httpRequest;

  /// The authentication key passed from the client.
  final String? authenticationKey;

  /// Creates a new [MethodCallInfo].
  MethodCallInfo({
    required this.uri,
    required this.body,
    required this.queryParameters,
    required this.endpointName,
    required this.methodName,
    required this.httpRequest,
    this.authenticationKey,
  });
}

/// Information associated with a [FutureCall].
class FutureCallInfo {
  /// Name of the [FutureCall].
  final String callName;

  /// Creates a new [FutureCallInfo].
  FutureCallInfo({
    required this.callName,
  });
}