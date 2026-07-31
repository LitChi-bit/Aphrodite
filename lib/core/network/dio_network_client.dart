import 'package:dio/dio.dart';

import '../errors/app_exception.dart';
import 'access_token_provider.dart';
import 'network_client.dart';

final class DioNetworkClient implements NetworkClient {
  DioNetworkClient({
    required String baseUrl,
    required AccessTokenProvider accessTokenProvider,
    AccessTokenRefresher? Function()? accessTokenRefresher,
    Dio? dio,
  })  : _accessTokenProvider = accessTokenProvider,
        _accessTokenRefresher = accessTokenRefresher,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
                headers: const <String, Object>{
                  'Accept': 'application/json',
                },
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final accessToken = _accessTokenProvider.accessToken;
          if (accessToken == null || accessToken.isEmpty) {
            options.headers.remove('Authorization');
          } else {
            options.headers['Authorization'] = 'Bearer $accessToken';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final retried = await _retryAfterUnauthorized(error);
          if (retried != null) {
            handler.resolve(retried);
            return;
          }
          handler.next(error);
        },
      ),
    );
  }

  static const _retriedKey = 'aphrodite.auth.retried';

  final AccessTokenProvider _accessTokenProvider;
  final AccessTokenRefresher? Function()? _accessTokenRefresher;
  final Dio _dio;
  Future<String?>? _pendingRefresh;

  Future<Response<Object?>?> _retryAfterUnauthorized(DioException error) async {
    final request = error.requestOptions;
    if (error.response?.statusCode != 401 ||
        request.extra[_retriedKey] == true ||
        _isAuthRequest(request.path)) {
      return null;
    }

    final currentAccessToken = _accessTokenProvider.accessToken;
    if (_wasSentWithStaleToken(request, currentAccessToken)) {
      return _retry(request, currentAccessToken!);
    }

    String? refreshedAccessToken;
    try {
      refreshedAccessToken = await _refreshAccessToken();
    } catch (_) {
      return null;
    }
    if (refreshedAccessToken == null || refreshedAccessToken.isEmpty) {
      return null;
    }

    return _retry(request, refreshedAccessToken);
  }

  Future<Response<Object?>> _retry(
    RequestOptions request,
    String accessToken,
  ) {
    request.extra[_retriedKey] = true;
    request.headers['Authorization'] = 'Bearer $accessToken';
    return _dio.fetch<Object?>(request);
  }

  bool _wasSentWithStaleToken(
    RequestOptions request,
    String? currentAccessToken,
  ) {
    if (currentAccessToken == null || currentAccessToken.isEmpty) return false;
    return request.headers['Authorization'] != 'Bearer $currentAccessToken';
  }

  Future<String?> _refreshAccessToken() {
    final current = _pendingRefresh;
    if (current != null) return current;

    final refresher = _accessTokenRefresher?.call();
    if (refresher == null) return Future<String?>.value(null);

    final pending = refresher.refreshAccessToken();
    _pendingRefresh = pending;
    return pending.whenComplete(() => _pendingRefresh = null);
  }

  bool _isAuthRequest(String path) => path.startsWith('/v1/auth/');

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    try {
      final Response<Object?> response = await _dio.get<Object?>(
        path,
        queryParameters: queryParameters,
      );
      return response.data;
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<Object?> delete(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    try {
      final Response<Object?> response = await _dio.delete<Object?>(
        path,
        queryParameters: queryParameters,
      );
      return response.data;
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    try {
      final Response<Object?> response = await _dio.post<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return response.data;
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  NetworkException _mapError(DioException error) {
    final int? statusCode = error.response?.statusCode;
    final String message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        '网络请求超时',
      DioExceptionType.connectionError => '无法连接到服务器',
      DioExceptionType.badResponse => '服务器返回异常状态',
      DioExceptionType.cancel => '网络请求已取消',
      _ => '网络请求失败',
    };
    return NetworkException(message, cause: error, statusCode: statusCode);
  }
}
