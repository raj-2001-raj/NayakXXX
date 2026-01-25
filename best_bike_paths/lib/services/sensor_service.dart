import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorService {
  static const double _gravity = 9.8;
  static const double _zImpactThresholdG = 2.0;
  static const int _windowSize = 50;
  static const double _stdMultiplier = 3.0;
  static const double _jerkThresholdGPerSec = 6.0;
  static const double _highPassCutoffHz = 0.6;
  static const double _lowPassCutoffHz = 12.0;
  static const double _gyroCorrectionGain = 0.08;
  static const double _confidenceThreshold = 0.6;
  static const Duration _sampleInterval = Duration(milliseconds: 20);
  static const double _minSpeedKmh = 10;
  static const double _validMinSpeedKmh = 5;
  static const double _validMaxSpeedKmh = 35;
  static const Duration _cooldown = Duration(milliseconds: 500);

  StreamSubscription? _subscription;
  StreamSubscription? _gyroSubscription;
  Timer? _fallbackTimer;
  bool _usingAccelerometerFallback = false;
  bool _receivedEvent = false;
  DateTime? _lastSampleSent;

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  Function(Map<String, double>)? _onDebug;

  void startListening(
    Function() onPotholeDetected, {
    Function(Map<String, double>)? onDebug,
  }) {
    _subscription?.cancel();
    _fallbackTimer?.cancel();
    _usingAccelerometerFallback = false;
    _receivedEvent = false;
    _lastSampleSent = null;
    _onDebug = onDebug;

    _startIsolate(onPotholeDetected);

    _gyroSubscription?.cancel();
    _gyroSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      _sendToIsolate({
        'type': 'gyro',
        'x': event.x,
        'y': event.y,
        'z': event.z,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });

    // Try to use the "User" accelerometer first (ignores gravity)
    _subscription = userAccelerometerEvents.listen(
      (UserAccelerometerEvent event) {
        _receivedEvent = true;
        _handleForce(event.x, event.y, event.z, onPotholeDetected);
      },
      onError: (error, _) {
        debugPrint('Linear sensor error. Switching to fallback...');
        _switchToAccelerometer(onPotholeDetected);
      },
    );

    // If no data comes in 2 seconds, switch to the basic accelerometer
    _fallbackTimer = Timer(const Duration(seconds: 2), () {
      if (!_receivedEvent) {
        debugPrint('No linear events. Switching to basic accelerometer...');
        _switchToAccelerometer(onPotholeDetected);
      }
    });
  }

  void _switchToAccelerometer(Function() onPotholeDetected) {
    if (_usingAccelerometerFallback) return;
    _usingAccelerometerFallback = true;
    _fallbackTimer?.cancel();
    _subscription?.cancel();

    _subscription = accelerometerEvents.listen((AccelerometerEvent event) {
      _handleForce(event.x, event.y, event.z, onPotholeDetected);
    });
  }

  void updateSpeed(double speedMps) {
    _sendToIsolate({
      'type': 'speed',
      'speed': speedMps,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void setTestMode(bool enabled) {
    _sendToIsolate({
      'type': 'config',
      'testMode': enabled,
    });
  }

  void _handleForce(
    double x,
    double y,
    double z,
    Function() onPotholeDetected,
  ) {
    final now = DateTime.now();
    if (_lastSampleSent != null &&
        now.difference(_lastSampleSent!) < _sampleInterval) {
      return;
    }
    _lastSampleSent = now;

    _sendToIsolate({
      'type': 'sample',
      'x': x,
      'y': y,
      'z': z,
      'fallback': _usingAccelerometerFallback,
      'timestamp': now.millisecondsSinceEpoch,
    });
  }

  void stopListening() {
    _fallbackTimer?.cancel();
    _subscription?.cancel();
    _gyroSubscription?.cancel();
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  void _startIsolate(Function() onPotholeDetected) async {
    _receivePort?.close();
    _receivePort = ReceivePort();
    _receivePort!.listen((message) {
      if (message == 'detected') {
        onPotholeDetected();
      } else if (message is Map && message['type'] == 'debug') {
        final payload = Map<String, double>.from(message['data'] as Map);
        _onDebug?.call(payload);
      } else if (message is SendPort) {
        _sendPort = message;
      }
    });

    _isolate = await Isolate.spawn(
      _potholeIsolateEntry,
      _receivePort!.sendPort,
    );
  }

  void _sendToIsolate(Map<String, dynamic> message) {
    if (_sendPort != null) {
      _sendPort!.send(message);
    }
  }

  static void _potholeIsolateEntry(SendPort mainSendPort) {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    double latestSpeedMps = 0;
    DateTime? lastDetection;
    final List<double> zWindow = [];
    double? lastZForceG;
    DateTime? lastSampleTime;
    DateTime? lastDebugSend;
    DateTime? lastGyroTime;
    DateTime? lastFilterTime;
    double rawPrev = 0;
    double highPassPrev = 0;
    double lowPassPrev = 0;
    List<double>? lastAccelDir;

    double q0 = 1;
    double q1 = 0;
    double q2 = 0;
    double q3 = 0;
  bool testMode = false;

    List<double> rotateVector(
      double q0,
      double q1,
      double q2,
      double q3,
      List<double> v,
    ) {
      final x = v[0];
      final y = v[1];
      final z = v[2];
      final ix = q0 * x + q2 * z - q3 * y;
      final iy = q0 * y + q3 * x - q1 * z;
      final iz = q0 * z + q1 * y - q2 * x;
      final iw = -q1 * x - q2 * y - q3 * z;
      return [
        ix * q0 + iw * -q1 + iy * -q3 - iz * -q2,
        iy * q0 + iw * -q2 + iz * -q1 - ix * -q3,
        iz * q0 + iw * -q3 + ix * -q2 - iy * -q1,
      ];
    }

    List<double> normalizeVec(List<double> v) {
      final mag = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
      if (mag == 0) return [0, 0, 0];
      return [v[0] / mag, v[1] / mag, v[2] / mag];
    }

    List<double> cross(List<double> a, List<double> b) {
      return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
      ];
    }

    void normalizeQuat() {
      final norm = sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3);
      if (norm == 0) {
        q0 = 1;
        q1 = 0;
        q2 = 0;
        q3 = 0;
        return;
      }
      q0 /= norm;
      q1 /= norm;
      q2 /= norm;
      q3 /= norm;
    }

    void integrateGyro(
      double gx,
      double gy,
      double gz,
      double dt,
    ) {
      final halfDt = 0.5 * dt;
      final dq0 = (-q1 * gx - q2 * gy - q3 * gz) * halfDt;
      final dq1 = (q0 * gx + q2 * gz - q3 * gy) * halfDt;
      final dq2 = (q0 * gy - q1 * gz + q3 * gx) * halfDt;
      final dq3 = (q0 * gz + q1 * gy - q2 * gx) * halfDt;
      q0 += dq0;
      q1 += dq1;
      q2 += dq2;
      q3 += dq3;
      normalizeQuat();
    }

    port.listen((dynamic message) {
      if (message is! Map) return;
      final type = message['type'];

      if (type == 'speed') {
        latestSpeedMps = (message['speed'] as num).toDouble();
        return;
      }

      if (type == 'config') {
        testMode = message['testMode'] == true;
        return;
      }

      if (type == 'gyro') {
        final gx = (message['x'] as num).toDouble();
        final gy = (message['y'] as num).toDouble();
        final gz = (message['z'] as num).toDouble();
        final timestamp = message['timestamp'] as int?;
        if (timestamp == null) return;
        final now = DateTime.fromMillisecondsSinceEpoch(timestamp);
        if (lastGyroTime != null) {
          final dt = now.difference(lastGyroTime!).inMilliseconds / 1000.0;
          if (dt > 0) {
            var adjGx = gx;
            var adjGy = gy;
            var adjGz = gz;
            if (lastAccelDir != null) {
              final gravityDevice = rotateVector(q0, -q1, -q2, -q3, [0, 0, 1]);
              final error = cross(gravityDevice, lastAccelDir!);
              adjGx += error[0] * _gyroCorrectionGain;
              adjGy += error[1] * _gyroCorrectionGain;
              adjGz += error[2] * _gyroCorrectionGain;
            }
            integrateGyro(adjGx, adjGy, adjGz, dt);
          }
        }
        lastGyroTime = now;
        return;
      }

      if (type != 'sample') return;

      final x = (message['x'] as num).toDouble();
      final y = (message['y'] as num).toDouble();
      final z = (message['z'] as num).toDouble();
      final fallback = message['fallback'] == true;
      final timestamp = message['timestamp'] as int?;
      final now = timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : DateTime.now();

      final totalForce = sqrt(x * x + y * y + z * z);
      if (fallback && totalForce > 0) {
        lastAccelDir = normalizeVec([x, y, z]);
      }

      final accelDevice = [x, y, z];
      final accelWorld = rotateVector(q0, q1, q2, q3, accelDevice);
      final linearWorld = fallback
          ? [
              accelWorld[0],
              accelWorld[1],
              accelWorld[2] - _gravity,
            ]
          : accelWorld;

      final rawZ = linearWorld[2] / _gravity;
      final rawAbsZ = rawZ.abs();

      double filteredZ = rawZ;
      if (lastFilterTime != null) {
        final dt = now.difference(lastFilterTime!).inMilliseconds / 1000.0;
        if (dt > 0) {
          final rcHigh = 1 / (2 * pi * _highPassCutoffHz);
          final alphaHigh = rcHigh / (rcHigh + dt);
          final highPass = alphaHigh * (highPassPrev + rawZ - rawPrev);

          final rcLow = 1 / (2 * pi * _lowPassCutoffHz);
          final alphaLow = dt / (rcLow + dt);
          final lowPass = lowPassPrev + alphaLow * (highPass - lowPassPrev);

          rawPrev = rawZ;
          highPassPrev = highPass;
          lowPassPrev = lowPass;
          filteredZ = lowPass;
        }
      } else {
        rawPrev = rawZ;
        highPassPrev = rawZ;
        lowPassPrev = rawZ;
      }
      lastFilterTime = now;

      final zForceG = filteredZ.abs();

      final speedKmh = latestSpeedMps * 3.6;
      if (!testMode) {
        if (speedKmh < _validMinSpeedKmh || speedKmh > _validMaxSpeedKmh) {
          return;
        }
        if (speedKmh < _minSpeedKmh) {
          return;
        }
      }

      zWindow.add(zForceG);
      if (zWindow.length > _windowSize) {
        zWindow.removeAt(0);
      }

      double jerkGPerSec = 0;
      if (lastZForceG != null && lastSampleTime != null) {
        final dt = now.difference(lastSampleTime!).inMilliseconds / 1000.0;
        if (dt > 0) {
          jerkGPerSec = (zForceG - lastZForceG!).abs() / dt;
        }
      }
      lastZForceG = zForceG;
      lastSampleTime = now;

      if (lastDetection != null &&
          now.difference(lastDetection!) < _cooldown) {
        return;
      }

    final adaptiveThreshold = _computeAdaptiveThreshold(zWindow);
    final threshold = testMode
      ? min(0.9, _zImpactThresholdG)
      : (adaptiveThreshold > _zImpactThresholdG
        ? adaptiveThreshold
        : _zImpactThresholdG);

    final jerkThreshold =
      testMode ? _jerkThresholdGPerSec * 0.4 : _jerkThresholdGPerSec;
    final zScore = ((zForceG - threshold) / threshold).clamp(0.0, 1.0);
    final jerkScore = (jerkGPerSec / jerkThreshold).clamp(0.0, 1.0);
    final speedScore = ((speedKmh - _minSpeedKmh) /
        (_validMaxSpeedKmh - _minSpeedKmh))
      .clamp(0.0, 1.0);
    final confidence =
      (zScore * 0.5) + (jerkScore * 0.3) + (speedScore * 0.2);
    final confidenceThreshold =
      testMode ? _confidenceThreshold * 0.4 : _confidenceThreshold;

      if (kDebugMode) {
        debugPrint(
          'Zg: ${zForceG.toStringAsFixed(2)} | raw: ${rawAbsZ.toStringAsFixed(2)} | ${speedKmh.toStringAsFixed(1)} km/h',
        );
      }

      final debugNow = DateTime.now();
      if (kDebugMode &&
          (lastDebugSend == null ||
              debugNow.difference(lastDebugSend!) >
                  const Duration(milliseconds: 200))) {
        lastDebugSend = debugNow;
        mainSendPort.send({
          'type': 'debug',
          'data': {
            'zForceG': zForceG,
            'rawZ': rawAbsZ,
            'jerk': jerkGPerSec,
            'speedKmh': speedKmh,
            'threshold': threshold,
            'confidence': confidence,
            'testMode': testMode ? 1.0 : 0.0,
          },
        });
      }

      if (zForceG >= threshold &&
          jerkGPerSec >= jerkThreshold &&
          confidence >= confidenceThreshold) {
        lastDetection = now;
        mainSendPort.send('detected');
      }
    });
  }

  static double _computeAdaptiveThreshold(List<double> window) {
    if (window.length < 10) {
      return _zImpactThresholdG;
    }
    final mean = window.reduce((a, b) => a + b) / window.length;
    double variance = 0;
    for (final value in window) {
      variance += (value - mean) * (value - mean);
    }
    variance /= window.length;
    final stdDev = sqrt(variance);
    return mean + (_stdMultiplier * stdDev);
  }
}
