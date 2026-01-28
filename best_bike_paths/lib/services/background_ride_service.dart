import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Service to manage background ride tracking
class BackgroundRideService {
  static final BackgroundRideService _instance = BackgroundRideService._internal();
  factory BackgroundRideService() => _instance;
  BackgroundRideService._internal();

  bool _isInitialized = false;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Initialize the foreground task (call once at app start)
  Future<void> initialize() async {
    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ride_tracking_channel',
        channelName: 'Ride Tracking',
        channelDescription: 'Shows when a ride is being tracked',
        channelImportance: NotificationChannelImportance.MAX,  // Maximum priority
        priority: NotificationPriority.MAX,  // Maximum priority
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000), // Update every 1 second for sensors
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
    debugPrint('[BACKGROUND] Service initialized with MAX priority');
  }

  /// Start background tracking for a ride
  Future<bool> startBackgroundTracking() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Request permissions
    final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Check if we can start
    if (await FlutterForegroundTask.isRunningService) {
      debugPrint('[BACKGROUND] Service already running');
      _isRunning = true;
      return true;
    }

    // Enable wakelock to prevent CPU from sleeping
    await WakelockPlus.enable();
    debugPrint('[BACKGROUND] Wakelock enabled');

    // Start the foreground service
    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'Ride in Progress 🚴',
      notificationText: 'Tracking your route...',
      callback: _startCallback,
    );

    _isRunning = result is ServiceRequestSuccess;
    debugPrint('[BACKGROUND] Service started: $_isRunning');
    return _isRunning;
  }

  /// Update the notification with current ride stats
  Future<void> updateNotification({
    required double distanceKm,
    required Duration duration,
    required double speedKmh,
  }) async {
    if (!_isRunning) return;

    final durationStr = _formatDuration(duration);
    final distanceStr = distanceKm.toStringAsFixed(2);
    final speedStr = speedKmh.toStringAsFixed(1);

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Ride in Progress 🚴',
      notificationText: '$distanceStr km • $durationStr • $speedStr km/h',
    );
  }

  /// Stop background tracking
  Future<void> stopBackgroundTracking() async {
    if (!_isRunning) return;

    // Disable wakelock
    await WakelockPlus.disable();
    debugPrint('[BACKGROUND] Wakelock disabled');

    // Stop the foreground service
    await FlutterForegroundTask.stopService();
    _isRunning = false;
    debugPrint('[BACKGROUND] Service stopped');
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

// Callback function for the foreground task
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_RideTaskHandler());
}

/// Task handler that runs in the background
class _RideTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionStream;
  int _updateCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BACKGROUND TASK] Started at $timestamp by $starter');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _updateCount++;
    // This runs periodically (every 5 seconds as configured)
    // The main app handles actual location tracking
    // This just keeps the service alive
    debugPrint('[BACKGROUND TASK] Heartbeat #$_updateCount at $timestamp');
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[BACKGROUND TASK] Destroyed at $timestamp');
    await _positionStream?.cancel();
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('[BACKGROUND TASK] Received data: $data');
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('[BACKGROUND TASK] Button pressed: $id');
    if (id == 'stop') {
      // Send message to main app to stop the ride
      FlutterForegroundTask.sendDataToMain({'action': 'stop_ride'});
    }
  }

  @override
  void onNotificationPressed() {
    debugPrint('[BACKGROUND TASK] Notification pressed - opening app');
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    debugPrint('[BACKGROUND TASK] Notification dismissed');
  }
}
