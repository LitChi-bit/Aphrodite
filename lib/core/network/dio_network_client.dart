import 'package:dio/dio.dart';

import '../errors/app_exception.dart';
import 'network_client.dart';

final class DioNetworkClient implements NetworkClient {
  DioNetworkClient({required String baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 20),
            headers: const <String, Object>{
              'Accept': 'application/json',
            },
          ),
        );

  final Dio _dio;

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
