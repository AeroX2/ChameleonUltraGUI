import 'dart:typed_data';

class LfTuneStatus {
  final int frequencyKHz;
  final int actualFrequencyHz;

  const LfTuneStatus(this.frequencyKHz, this.actualFrequencyHz);

  factory LfTuneStatus.fromBytes(Uint8List data) {
    if (data.length != 5) {
      throw const FormatException('Malformed LF tune status');
    }
    final actual = (data[1] << 24) | (data[2] << 16) | (data[3] << 8) | data[4];
    return LfTuneStatus(data[0], actual);
  }
}

class LfTunePoint {
  final int frequencyKHz;
  final int mean;
  final int min;
  final int max;

  const LfTunePoint(this.frequencyKHz, this.mean, this.min, this.max);
}

class LfTuneSweep {
  final int originalFrequencyKHz;
  final List<LfTunePoint> points;

  const LfTuneSweep(this.originalFrequencyKHz, this.points);

  factory LfTuneSweep.fromBytes(Uint8List data) {
    if (data.length < 2 || data.length != 2 + data[1] * 4) {
      throw const FormatException('Malformed LF tune sweep');
    }
    return LfTuneSweep(
      data[0],
      List.generate(data[1], (index) {
        final offset = 2 + index * 4;
        return LfTunePoint(
          data[offset],
          data[offset + 1],
          data[offset + 2],
          data[offset + 3],
        );
      }),
    );
  }

  LfTunePoint? get strongest {
    if (points.isEmpty) return null;
    return points.reduce((a, b) => b.mean > a.mean ? b : a);
  }
}
