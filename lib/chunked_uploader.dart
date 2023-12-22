// ignore_for_file: avoid_print, require_trailing_commas

library chunked_uploader;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:async/async.dart';
import 'package:dio/dio.dart';

/// Uploads large files by chunking them into smaller parts
class ChunkedUploader {
  final Dio _dio;

  const ChunkedUploader(this._dio);

  /// Uploads the file using it's data stream
  /// Suitable for Web platform since the file path isn't available
  Future<Response?> upload({
    required Stream<List<int>> fileDataStream,
    required String fileName,
    required int fileSize,
    required String path,
    Map<String, dynamic>? data,
    CancelToken? cancelToken,
    int? maxChunkSize,
    Function(double)? onUploadProgress,
    ChunkHeadersCallback? headersCallback,
    String method = 'POST',
    String fileKey = 'file',
  }) =>
      _Uploader(
        _dio,
        fileDataStream: fileDataStream,
        fileName: fileName,
        fileSize: fileSize,
        path: path,
        fileKey: fileKey,
        method: method,
        data: data,
        cancelToken: cancelToken,
        maxChunkSize: maxChunkSize,
        onUploadProgress: onUploadProgress,
        headersCallback: headersCallback,
      ).upload();

  /// Uploads the file using it's path
  Future<Response?> uploadUsingFilePath({
    required String filePath,
    required String fileName,
    required String path,
    Map<String, dynamic>? data,
    CancelToken? cancelToken,
    int? maxChunkSize,
    Function(double)? onUploadProgress,
    Function(double)? chunkSize,
    ChunkHeadersCallback? headersCallback,
    String method = 'POST',
    String fileKey = 'file',
  }) =>
      _Uploader.fromFilePath(
        _dio,
        filePath: filePath,
        fileName: fileName,
        path: path,
        fileKey: fileKey,
        method: method,
        data: data,
        cancelToken: cancelToken,
        maxChunkSize: maxChunkSize,
        onUploadProgress: onUploadProgress,
        headersCallback: headersCallback,
        chunkSize: chunkSize,
      ).upload();
}

class _Uploader {
  final Dio dio;
  late final int fileSize;
  late final ChunkedStreamReader<int> streamReader;
  final String fileName, path, fileKey;
  final String? method;
  final Map<String, dynamic>? data;
  final CancelToken? cancelToken;
  final Function(double)? onUploadProgress;
  final Function(double)? chunkSize;
  late int _maxChunkSize;
  final ChunkHeadersCallback _headersCallback;

  _Uploader(
    this.dio, {
    required Stream<List<int>> fileDataStream,
    required this.fileName,
    required this.fileSize,
    required this.path,
    required this.fileKey,
    this.chunkSize,
    this.method,
    this.data,
    this.cancelToken,
    this.onUploadProgress,
    ChunkHeadersCallback? headersCallback,
    int? maxChunkSize,
  })  : streamReader = ChunkedStreamReader(fileDataStream),
        _maxChunkSize = min(fileSize, maxChunkSize ?? fileSize),
        _headersCallback = headersCallback ?? _defaultHeadersCallback;

  _Uploader.fromFilePath(
    this.dio, {
    required String filePath,
    required this.fileName,
    required this.path,
    required this.fileKey,
    this.method,
    this.data,
    this.cancelToken,
    this.onUploadProgress,
    this.chunkSize,
    ChunkHeadersCallback? headersCallback,
    int? maxChunkSize,
  }) : _headersCallback = headersCallback ?? _defaultHeadersCallback {
    final file = File(filePath);
    streamReader = ChunkedStreamReader(file.openRead());
    fileSize = file.lengthSync();
    _maxChunkSize = min(fileSize, maxChunkSize ?? fileSize);
  }

  Future<Response?> uploadSingleChunk({
    required int start,
    required FormData formData,
    required int currentIndex,
  }) async {
    var headers = {'Cookie': 'ci_session=${data!["accessToken"]}'};
    Response? finalResponse;
    print(
        'INSIDE API CALL WITH PARMS :: START $start , ID CONTENT ${data!["idContent"]}');
    try {
      // var mapData = {
      //   "Upsert": {
      //     "idContent": data!["idContent"] ?? "",
      //     "UploadedFileSize": start + 1,
      //   }
      // };
      finalResponse = await dio.request(
        path,
        data: formData,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          headers: headers,
        ),
        onSendProgress: (current, total) =>
            _updateProgress(currentIndex, current, total),
      );
    } catch (e) {
      print('Inside API CATCH $e');
    } finally {
      print('Inside FINALLY BLOCK API RETURNED THIS VALUE BELOW');
      print('${finalResponse?.data.toString()}' + ' API RESPONSE <+++');
      return finalResponse;
    }
  }

  Future<Response?> upload() async {
    try {
      Response? finalResponse;
      for (int i = 0; i < _chunksCount; i++) {
        final start = _getChunkStart(i);
        final end = _getChunkEnd(i);
        final chunkStream = _getChunkStream();

        print(
            'THE CHUNK WE ARE AT at ith pos{$i}===> ${end - start} of chunkcount $_chunksCount and starts at ${start + 1} == endSize at ${end} ');

        final formData = FormData.fromMap({
          "files": [
            MultipartFile(chunkStream, end - start, filename: fileName)
          ],
          'Upsert': jsonEncode({
            "idContent": data!["idContent"] ?? "",
            "UploadedFileSize": start + 1,
          }),
        });
        // chunkString +=
        //     "${inspect(MultipartFile(chunkStream, end - start, filename: fileName))}}";

        finalResponse = await uploadSingleChunk(
          start: start,
          formData: formData,
          currentIndex: i,
        );
      }

      return finalResponse;
    } catch (_) {
      rethrow;
    } finally {
      streamReader.cancel();
    }
  }

  Stream<List<int>> _getChunkStream() => streamReader.readStream(_maxChunkSize);

  // Updating total upload progress
  void _updateProgress(int chunkIndex, int chunkCurrent, int chunkTotal) {
    int totalUploadedSize = (chunkIndex * _maxChunkSize) + chunkCurrent;
    double totalUploadProgress = totalUploadedSize / fileSize;
    chunkSize?.call(((chunkIndex * _maxChunkSize) - chunkCurrent).toDouble());
    onUploadProgress?.call(totalUploadProgress);
  }

  // Returning start byte offset of current chunk
  int _getChunkStart(int chunkIndex) => chunkIndex * _maxChunkSize;

  // Returning end byte offset of current chunk
  int _getChunkEnd(int chunkIndex) =>
      min((chunkIndex + 1) * _maxChunkSize, fileSize);

  // Returning chunks count based on file size and maximum chunk size
  int get _chunksCount => (fileSize / _maxChunkSize).ceil();
}

typedef ChunkHeadersCallback = Map<String, dynamic> Function(
    int start, int end, int fileSize);

// Based on RFC 7233 (https://tools.ietf.org/html/rfc7233#section-2)
final ChunkHeadersCallback _defaultHeadersCallback =
    (int start, int end, int fileSize) =>
        {'Content-Range': 'bytes $start-${end - 1}/$fileSize'};
