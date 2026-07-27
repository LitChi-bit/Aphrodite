abstract interface class NetworkClient {
  Future<Object?> get(
    String path, {
    Map<String, Object?>? queryParameters,
  });

  Future<Object?> post(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  });
}
