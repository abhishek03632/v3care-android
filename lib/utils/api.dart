import 'dart:io';

import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

class API {
  final Dio _dio = Dio();

  /// LIVE URL
  //var imageBaseUrl = "https://agsdemo.in/v3careapi";
  //var imageBaseUrl = "https://v3care.in/crmapi";
  var imageBaseUrl = "https://api.v3care.in";

  /// TEST URL
  //var imageBaseUrl = "https://agscare.site/crmapi";

  /// Called when the server says the session is no longer valid (401).
  /// Wired up from main.dart so this file stays free of UI/navigation imports.
  static void Function()? onSessionExpired;

  /// TEST URL
  API() {
    /// LIVE URL
    // _dio.options.baseUrl = "https://agsdemo.in/v3careapi/public/api/";
    // _dio.options.baseUrl = "https://v3care.in/crmapi/public/api/";
    _dio.options.baseUrl = "https://api.v3care.in/api/";

    /// TEST URL
    //_dio.options.baseUrl = "https://agscare.site/crmapi/public/api/";

    // _dio.options.baseUrl = "https://agsdraft.online/app/public/api/";
    //_dio.options.baseUrl = "https://agstest.online/public/api/";

    // Laravel picks between "401 JSON" and "302 redirect to the login page"
    // based on this header. Without it an expired token answers a POST with a
    // 302, which dart:io refuses to follow on POST, so Dio raised it as
    // `DioException [bad response] ... 302` straight into the user's face.
    _dio.options.headers[HttpHeaders.acceptHeader] = 'application/json';

    // Previously unset: a stalled connection hung the request forever and left
    // the loader spinning with no way out.
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
    _dio.options.sendTimeout = const Duration(seconds: 60);

    _dio.interceptors.add(_RedirectAndAuthInterceptor(_dio));
    _dio.interceptors.add(PrettyDioLogger(
      request: false,
      responseBody: false,
    ));
  }

  Dio get dio => _dio;

  /// Human-readable text for any error thrown by a request, so screens never
  /// print a raw `DioException` to the user.
  static String friendlyMessage(Object? error) {
    if (error is! DioException) {
      return "Sorry, something went wrong.\nPlease try again later.";
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return "The server is taking too long to respond.\nPlease try again.";
      case DioExceptionType.connectionError:
        return "Unable to reach the server.\nPlease check your internet connection.";
      case DioExceptionType.cancel:
        return "The request was cancelled.";
      case DioExceptionType.badCertificate:
        return "Could not establish a secure connection to the server.";
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        {
          final int? status = error.response?.statusCode;
          if (status == 401 || status == 403) {
            return "Your session has expired.\nPlease log in again.";
          }
          if (status != null && status >= 500) {
            return "The server is temporarily unavailable.\nPlease try again in a few minutes.";
          }
          final dynamic data = error.response?.data;
          if (data is Map && data['message'] is String) {
            return data['message'] as String;
          }
          if (data is Map && data['msg'] is String) {
            return data['msg'] as String;
          }
          return "Sorry, something went wrong.\nPlease try again later.";
        }
    }
    // Unreachable today, but keeps this safe if dio adds an exception type.
    // ignore: dead_code
    return "Sorry, something went wrong.\nPlease try again later.";
  }
}

/// Handles the two things that were surfacing as raw exceptions:
///   * a 3xx answer to a POST, which dart:io will not follow automatically
///     (it only auto-follows 303 for POST), and
///   * a 401, which means the stored token is dead and the user has to log in
///     again rather than keep hitting the same error on every screen.
class _RedirectAndAuthInterceptor extends Interceptor {
  _RedirectAndAuthInterceptor(this._dio);

  final Dio _dio;

  static const int _maxRedirects = 5;
  static const String _redirectCountKey = 'v3care_redirect_count';

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final int? status = err.response?.statusCode;

    if (status != null && _isRedirect(status)) {
      final Response<dynamic>? followed = await _followRedirect(err, status);
      if (followed != null) {
        handler.resolve(followed);
        return;
      }
    }

    if (status == 401) {
      API.onSessionExpired?.call();
    }

    handler.next(err);
  }

  /// Re-issues the request against the `Location` header. Returns null when the
  /// redirect cannot be followed safely, in which case the original error flows
  /// on untouched.
  Future<Response<dynamic>?> _followRedirect(
    DioException err,
    int status,
  ) async {
    final RequestOptions request = err.requestOptions;

    final int redirectCount = (request.extra[_redirectCountKey] as int?) ?? 0;
    if (redirectCount >= _maxRedirects) return null;

    final String? location =
        err.response?.headers.value(HttpHeaders.locationHeader);
    if (location == null || location.isEmpty) return null;

    final Uri target = request.uri.resolve(location);

    // Never follow a redirect that drops us back to cleartext: the request
    // carries a bearer token and must not be replayed over plain http.
    if (request.uri.scheme == 'https' && target.scheme != 'https') return null;

    // A 303 (and, per browser behaviour, a 301/302 that leaves our API) must
    // not replay the body; everything else keeps the original method.
    final bool sameHost = target.host == request.uri.host;
    final bool keepMethod = status == 307 || status == 308 || sameHost;
    final String method = (status == 303 || !keepMethod) ? 'GET' : request.method;

    final Map<String, dynamic> headers = Map<String, dynamic>.from(request.headers);
    if (!sameHost) {
      // Do not hand the token to a different host.
      headers.remove(HttpHeaders.authorizationHeader);
      headers.remove('Authorization');
    }

    // A FormData body is a single-use stream, so it has to be cloned before the
    // request can be sent a second time.
    final dynamic data = method == 'GET'
        ? null
        : (request.data is FormData
            ? (request.data as FormData).clone()
            : request.data);

    try {
      return await _dio.requestUri<dynamic>(
        target,
        data: data,
        options: Options(
          method: method,
          headers: headers,
          responseType: request.responseType,
          contentType: request.contentType,
          followRedirects: request.followRedirects,
          receiveTimeout: request.receiveTimeout,
          sendTimeout: request.sendTimeout,
          extra: <String, dynamic>{
            ...request.extra,
            _redirectCountKey: redirectCount + 1,
          },
        ),
      );
    } on DioException {
      return null;
    }
  }
}
