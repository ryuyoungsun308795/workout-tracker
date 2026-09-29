/// 운동 종류
enum ActivityType { running, hiking }

extension ActivityTypeLabel on ActivityType {
  String get label => this == ActivityType.running ? '러닝' : '등산';
}

/// GPS 한 점 (고도는 기압계/GPS 보정 후 값)
class GeoSample {
  final double lat;
  final double lng;
  final double? alt;
  final DateTime time;
  final double accuracy; // m
  final double speed; // m/s (GPS 보고값, 없으면 -1)

  const GeoSample({
    required this.lat,
    required this.lng,
    required this.time,
    this.alt,
    this.accuracy = 5,
    this.speed = -1,
  });

  Map<String, dynamic> toJson() => {
        'la': lat,
        'ln': lng,
        'a': alt,
        't': time.millisecondsSinceEpoch,
        'ac': accuracy,
        's': speed,
      };

  factory GeoSample.fromJson(Map<String, dynamic> j) => GeoSample(
        lat: (j['la'] as num).toDouble(),
        lng: (j['ln'] as num).toDouble(),
        alt: (j['a'] as num?)?.toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        accuracy: (j['ac'] as num?)?.toDouble() ?? 5,
        speed: (j['s'] as num?)?.toDouble() ?? -1,
      );
}

/// 지도·그래프용 경로 점
class TrackPoint {
  final double lat;
  final double lng;
  final double? alt;
  final DateTime time;
  final double distance; // 누적 이동거리(m)
  final double movingSec; // 누적 운동시간(초)
  final bool moving; // false = 휴식 중 찍힌 점

  const TrackPoint(this.lat, this.lng, this.alt, this.time, this.distance,
      this.movingSec, this.moving);

  List<dynamic> toJson() => [
        lat,
        lng,
        alt,
        time.millisecondsSinceEpoch,
        distance,
        movingSec,
        moving ? 1 : 0
      ];

  factory TrackPoint.fromJson(List<dynamic> j) => TrackPoint(
        (j[0] as num).toDouble(),
        (j[1] as num).toDouble(),
        (j[2] as num?)?.toDouble(),
        DateTime.fromMillisecondsSinceEpoch(j[3] as int),
        (j[4] as num).toDouble(),
        (j[5] as num).toDouble(),
        j[6] == 1,
      );
}

/// 1km 구간 기록
class Split {
  final int index; // 1부터
  final double distance; // 구간 거리(m) — 마지막 구간은 1000 미만
  final double seconds; // 구간 운동시간
  final double gain;
  final double loss;

  const Split(this.index, this.distance, this.seconds, this.gain, this.loss);

  /// 분/km 페이스(초)
  double get paceSecPerKm => distance > 0 ? seconds / distance * 1000 : 0;

  Map<String, dynamic> toJson() =>
      {'i': index, 'd': distance, 's': seconds, 'g': gain, 'l': loss};

  factory Split.fromJson(Map<String, dynamic> j) => Split(
        j['i'] as int,
        (j['d'] as num).toDouble(),
        (j['s'] as num).toDouble(),
        (j['g'] as num).toDouble(),
        (j['l'] as num).toDouble(),
      );
}

class RestInterval {
  final DateTime start;
  DateTime? end; // null = 진행 중
  final bool manual; // 수동 일시정지 여부

  RestInterval(this.start, {this.end, this.manual = false});

  double secondsUntil(DateTime now) =>
      ((end ?? now).difference(start).inMilliseconds / 1000).clamp(0, 1e12);

  Map<String, dynamic> toJson() => {
        's': start.millisecondsSinceEpoch,
        'e': end?.millisecondsSinceEpoch,
        'm': manual,
      };

  factory RestInterval.fromJson(Map<String, dynamic> j) => RestInterval(
        DateTime.fromMillisecondsSinceEpoch(j['s'] as int),
        end: j['e'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['e'] as int),
        manual: j['m'] as bool? ?? false,
      );
}

/// 신체 정보
class Profile {
  final double heightCm;
  final double weightKg;
  final double waistCm;
  final bool? male; // 체지방률 추정용(선택)

  const Profile({
    this.heightCm = 170,
    this.weightKg = 70,
    this.waistCm = 85,
    this.male,
  });

  bool get isDefault => this == const Profile();

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  /// 허리/키 비율 (0.5 이상이면 복부비만 위험)
  double get waistToHeight => waistCm / heightCm;

  /// RFM(상대지방량) 체지방률 추정 — 성별 입력 시에만
  double? get bodyFatPercent {
    if (male == null || waistCm <= 0) return null;
    return 64 - 20 * heightCm / waistCm + (male! ? 0 : 12);
  }

  Map<String, dynamic> toJson() =>
      {'h': heightCm, 'w': weightKg, 'wa': waistCm, 'm': male};

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        heightCm: (j['h'] as num).toDouble(),
        weightKg: (j['w'] as num).toDouble(),
        waistCm: (j['wa'] as num).toDouble(),
        male: j['m'] as bool?,
      );
}

/// 저장되는 운동 1건 결과
class Workout {
  final String id;
  final ActivityType type;
  final DateTime start;
  final DateTime end;
  final double distance; // m
  final double movingSec;
  final double restSec;
  final double kcal;
  final double gain;
  final double loss;
  final double? maxAlt;
  final double? minAlt;
  final double maxSpeed; // m/s
  final List<Split> splits;
  final List<TrackPoint> track;
  final List<RestInterval> rests;
  final Profile profile;

  const Workout({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    required this.distance,
    required this.movingSec,
    required this.restSec,
    required this.kcal,
    required this.gain,
    required this.loss,
    required this.maxAlt,
    required this.minAlt,
    required this.maxSpeed,
    required this.splits,
    required this.track,
    required this.rests,
    required this.profile,
  });

  double get avgPaceSecPerKm => distance > 0 ? movingSec / distance * 1000 : 0;
  double get avgSpeedKmh => movingSec > 0 ? distance / movingSec * 3.6 : 0;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'type': type.name,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'distance': distance,
        'movingSec': movingSec,
        'restSec': restSec,
        'kcal': kcal,
        'gain': gain,
        'loss': loss,
        'maxAlt': maxAlt,
        'minAlt': minAlt,
        'maxSpeed': maxSpeed,
        'splits': splits.map((s) => s.toJson()).toList(),
        'track': track.map((t) => t.toJson()).toList(),
        'rests': rests.map((r) => r.toJson()).toList(),
        'profile': profile.toJson(),
      };

  factory Workout.fromJson(Map<String, dynamic> j) => Workout(
        id: j['id'] as String,
        type: ActivityType.values.byName(j['type'] as String),
        start: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(j['end'] as int),
        distance: (j['distance'] as num).toDouble(),
        movingSec: (j['movingSec'] as num).toDouble(),
        restSec: (j['restSec'] as num).toDouble(),
        kcal: (j['kcal'] as num).toDouble(),
        gain: (j['gain'] as num).toDouble(),
        loss: (j['loss'] as num).toDouble(),
        maxAlt: (j['maxAlt'] as num?)?.toDouble(),
        minAlt: (j['minAlt'] as num?)?.toDouble(),
        maxSpeed: (j['maxSpeed'] as num).toDouble(),
        splits: (j['splits'] as List)
            .map((e) => Split.fromJson(e as Map<String, dynamic>))
            .toList(),
        track: (j['track'] as List)
            .map((e) => TrackPoint.fromJson(e as List<dynamic>))
            .toList(),
        rests: (j['rests'] as List)
            .map((e) => RestInterval.fromJson(e as Map<String, dynamic>))
            .toList(),
        profile: Profile.fromJson(j['profile'] as Map<String, dynamic>),
      );
}
