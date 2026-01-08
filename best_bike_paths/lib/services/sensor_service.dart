import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorService {
  // Lowered to 12.0 for easier testing on Emulator
  // (Gravity is ~9.8, so 12.0 requires a small shake)
  static const double _shakeThreshold = 12.0;

  StreamSubscription? _subscription;
  Timer? _fallbackTimer;
  bool _usingAccelerometerFallback = false;
  bool _receivedEvent = false;

  void startListening(Function() onPotholeDetected) {
    _subscription?.cancel();
    _fallbackTimer?.cancel();
    _usingAccelerometerFallback = false;
    _receivedEvent = false;

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

  void _handleForce(
    double x,
    double y,
    double z,
    Function() onPotholeDetected,
  ) {
    final double force = sqrt(x * x + y * y + z * z);

    // DEBUG PRINT: This will show you the number in the console!
    // If this prints ~9.8, it means it's detecting gravity.
    print("Force: ${force.toStringAsFixed(2)}");

    if (force > _shakeThreshold) {
      debugPrint("!!! POTHOLE DETECTED !!!");
      onPotholeDetected();
    }
  }

  void stopListening() {
    _fallbackTimer?.cancel();
    _subscription?.cancel();
  }
}
