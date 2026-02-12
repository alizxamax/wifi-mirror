enum CropAspectRatio {
  free,
  ratio16x9,
  ratio9x16,
  ratio4x3,
  ratio1x1;

  String get label {
    switch (this) {
      case CropAspectRatio.free:
        return 'Free';
      case CropAspectRatio.ratio16x9:
        return '16:9';
      case CropAspectRatio.ratio9x16:
        return '9:16';
      case CropAspectRatio.ratio4x3:
        return '4:3';
      case CropAspectRatio.ratio1x1:
        return '1:1';
    }
  }

  double? get value {
    switch (this) {
      case CropAspectRatio.free:
        return null;
      case CropAspectRatio.ratio16x9:
        return 16 / 9;
      case CropAspectRatio.ratio9x16:
        return 9 / 16;
      case CropAspectRatio.ratio4x3:
        return 4 / 3;
      case CropAspectRatio.ratio1x1:
        return 1;
    }
  }
}

class CropSettings {
  final double topPercent;
  final double bottomPercent;
  final double leftPercent;
  final double rightPercent;
  final CropAspectRatio aspectRatio;

  const CropSettings({
    this.topPercent = 0,
    this.bottomPercent = 0,
    this.leftPercent = 0,
    this.rightPercent = 0,
    this.aspectRatio = CropAspectRatio.free,
  });

  CropSettings copyWith({
    double? topPercent,
    double? bottomPercent,
    double? leftPercent,
    double? rightPercent,
    CropAspectRatio? aspectRatio,
  }) {
    return CropSettings(
      topPercent: topPercent ?? this.topPercent,
      bottomPercent: bottomPercent ?? this.bottomPercent,
      leftPercent: leftPercent ?? this.leftPercent,
      rightPercent: rightPercent ?? this.rightPercent,
      aspectRatio: aspectRatio ?? this.aspectRatio,
    );
  }
}
