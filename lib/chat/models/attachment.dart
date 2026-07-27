enum AttachmentKind { image, video, audio, file }

class Attachment {
  const Attachment({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.mimeType,
    required this.byteSize,
    required this.uri,
    this.thumbnailUri,
    this.width,
    this.height,
    this.duration,
  });

  final String id;
  final AttachmentKind kind;
  final String fileName;
  final String mimeType;
  final int byteSize;
  final Uri uri;
  final Uri? thumbnailUri;
  final int? width;
  final int? height;
  final Duration? duration;

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        kind: AttachmentKind.values.byName(json['kind'] as String),
        fileName: json['fileName'] as String,
        mimeType: json['mimeType'] as String,
        byteSize: json['byteSize'] as int,
        uri: Uri.parse(json['uri'] as String),
        thumbnailUri: json['thumbnailUri'] == null
            ? null
            : Uri.parse(json['thumbnailUri'] as String),
        width: json['width'] as int?,
        height: json['height'] as int?,
        duration: json['durationMs'] == null
            ? null
            : Duration(milliseconds: json['durationMs'] as int),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'fileName': fileName,
        'mimeType': mimeType,
        'byteSize': byteSize,
        'uri': uri.toString(),
        'thumbnailUri': thumbnailUri?.toString(),
        'width': width,
        'height': height,
        'durationMs': duration?.inMilliseconds,
      };
}
