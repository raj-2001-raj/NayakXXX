import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'pothole_detection_model.dart';

/// ML-powered pothole detection service using RandomForest model
/// trained on SimRa Berlin bike ride data
class MLPotholeDetectionService {
  // Window configuration - optimized for bike pothole detection
  static const int _windowDurationMs = 2000; // 2 second sliding window
  static const int _minSamplesPerWindow =
      25; // ~25 samples at 50Hz = 0.5 sec minimum
  static const double _predictionThreshold =
      0.65; // 65% ML confidence (model is trained on bike data)
  static const Duration _cooldown = Duration(
    milliseconds: 2500,
  ); // 2.5 sec between ML detections
  static const Duration _sampleInterval = Duration(
    milliseconds: 20,
  ); // 50Hz sampling
  static const double _minZRange =
      2.0; // Min Z-axis range (potholes cause 2-10 m/s² range)
  static const double _minSpeedMps = 1.5; // Min speed ~5.4 km/h (slow cycling)

  StreamSubscription? _accelSubscription;
  StreamSubscription? _gyroSubscription;

  final Queue<_SensorSample> _sampleWindow = Queue();
  DateTime? _lastDetection;
  DateTime? _lastSampleTime;
  double _currentSpeedMps = 0;
  bool _isListening = false;

  // Callbacks
  Function(double lat, double lon, double severity)? onPotholeDetected;
  Function(Map<String, dynamic>)? onDebug;

  // Current location (set externally from GPS)
  double? _currentLat;
  double? _currentLon;

  void setLocation(double lat, double lon) {
    _currentLat = lat;
    _currentLon = lon;
  }

  void updateSpeed(double speedMps) {
    _currentSpeedMps = speedMps;
  }

  void startListening({
    Function(double lat, double lon, double severity)? onDetected,
    Function(Map<String, dynamic>)? onDebugCallback,
  }) {
    if (_isListening) return;
    _isListening = true;

    onPotholeDetected = onDetected;
    onDebug = onDebugCallback;

    _sampleWindow.clear();
    _lastDetection = null;

    // Listen to accelerometer at 50Hz
    _accelSubscription = accelerometerEventStream(
      samplingPeriod: _sampleInterval,
    ).listen(_handleAccelerometerEvent);

    debugPrint('[ML_POTHOLE] Started ML pothole detection service');
  }

  void _handleAccelerometerEvent(AccelerometerEvent event) {
    final now = DateTime.now();

    // Rate limiting
    if (_lastSampleTime != null &&
        now.difference(_lastSampleTime!) < _sampleInterval) {
      return;
    }
    _lastSampleTime = now;

    // Add sample to window
    _sampleWindow.add(
      _SensorSample(
        x: event.x,
        y: event.y,
        z: event.z,
        timestamp: now.millisecondsSinceEpoch,
      ),
    );

    // Remove old samples (keep 2 second window)
    final cutoffTime = now.millisecondsSinceEpoch - _windowDurationMs;
    while (_sampleWindow.isNotEmpty &&
        _sampleWindow.first.timestamp < cutoffTime) {
      _sampleWindow.removeFirst();
    }

    // Check if we have enough samples and not in cooldown
    if (_sampleWindow.length >= _minSamplesPerWindow) {
      if (_lastDetection == null ||
          now.difference(_lastDetection!) > _cooldown) {
        _runPrediction();
      }
    }
  }

  void _runPrediction() {
    if (_sampleWindow.length < _minSamplesPerWindow) return;

    // Skip if not moving fast enough (avoids false positives when stationary)
    if (_currentSpeedMps < _minSpeedMps) {
      return;
    }

    // Compute features from the window
    final features = _computeFeatures();
    if (features == null) return;

    // Check if Z-range is significant enough (filters out small vibrations)
    final zRange = features[4];
    if (zRange < _minZRange) {
      return;
    }

    // Run ML prediction
    final probability = PotholeDetectionModel.predictProbability(features);

    // Debug output
    onDebug?.call({
      'ml_probability': probability,
      'z_mean': features[0],
      'z_std': features[1],
      'z_min': features[2],
      'z_max': features[3],
      'z_range': features[4],
      'sample_count': _sampleWindow.length,
      'speed_mps': _currentSpeedMps,
    });

    // Check if pothole detected - ML model is trained on bike data
    // Use probability threshold, z_range confirms it's a real impact
    if (probability > _predictionThreshold && zRange >= _minZRange) {
      _lastDetection = DateTime.now();

      // Calculate severity (0-1 based on z_range and probability)
      // Bike potholes typically have z_range of 2-15 m/s²
      final zSeverity = ((zRange - _minZRange) / 10.0).clamp(0.0, 1.0);
      final severity = (zSeverity * 0.6 + probability * 0.4).clamp(0.0, 1.0);

      debugPrint(
        '[ML_POTHOLE] Detected! Probability: ${probability.toStringAsFixed(2)}, '
        'Severity: ${severity.toStringAsFixed(2)}, Z-range: ${zRange.toStringAsFixed(2)}',
      );

      // Trigger callback with location and severity
      if (_currentLat != null && _currentLon != null) {
        onPotholeDetected?.call(_currentLat!, _currentLon!, severity);
      }
    }
  }

  /// Compute features from the sensor window
  /// Returns: [z_mean, z_std, z_min, z_max, z_range, x_mean, x_std, x_range, y_mean, y_std, y_range]
  List<double>? _computeFeatures() {
    if (_sampleWindow.isEmpty) return null;

    final zValues = _sampleWindow.map((s) => s.z).toList();
    final xValues = _sampleWindow.map((s) => s.x).toList();
    final yValues = _sampleWindow.map((s) => s.y).toList();

    // Z-axis features (most important for pothole detection)
    final zMean = _mean(zValues);
    final zStd = _std(zValues, zMean);
    final zMin = zValues.reduce(min);
    final zMax = zValues.reduce(max);
    final zRange = zMax - zMin;

    // X-axis features
    final xMean = _mean(xValues);
    final xStd = _std(xValues, xMean);
    final xRange = xValues.reduce(max) - xValues.reduce(min);

    // Y-axis features
    final yMean = _mean(yValues);
    final yStd = _std(yValues, yMean);
    final yRange = yValues.reduce(max) - yValues.reduce(min);

    return [
      zMean,
      zStd,
      zMin,
      zMax,
      zRange,
      xMean,
      xStd,
      xRange,
      yMean,
      yStd,
      yRange,
    ];
  }

  double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _std(List<double> values, double mean) {
    if (values.isEmpty) return 0.0;
    final variance =
        values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
        values.length;
    return sqrt(variance);
  }

  void stopListening() {
    _isListening = false;
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _sampleWindow.clear();
    debugPrint('[ML_POTHOLE] Stopped ML pothole detection service');
  }

  bool get isListening => _isListening;
}

class _SensorSample {
  final double x;
  final double y;
  final double z;
  final int timestamp;

  _SensorSample({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  });
}
