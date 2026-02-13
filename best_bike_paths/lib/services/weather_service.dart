import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Weather conditions that affect cycling safety
enum WeatherCondition { clear, cloudy, rain, heavyRain, snow, fog, wind, storm }

/// Weather alert severity levels
enum AlertSeverity {
  info, // Just informational
  warning, // Be cautious
  danger, // Consider not riding
}

/// Represents current weather data
class WeatherData {
  final double temperature; // Celsius
  final double humidity; // Percentage
  final double windSpeed; // m/s
  final WeatherCondition condition;
  final String description;
  final DateTime timestamp;
  final List<WeatherAlert> alerts;

  const WeatherData({
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.condition,
    required this.description,
    required this.timestamp,
    this.alerts = const [],
  });

  /// Check if weather is safe for cycling
  bool get isSafeForCycling {
    if (condition == WeatherCondition.storm) return false;
    if (condition == WeatherCondition.heavyRain) return false;
    if (condition == WeatherCondition.snow) return false;
    if (windSpeed > 15) return false; // > 54 km/h wind
    return true;
  }

  /// Get cycling-specific advice based on weather
  String get cyclingAdvice {
    final advices = <String>[];

    if (condition == WeatherCondition.rain ||
        condition == WeatherCondition.heavyRain) {
      advices.add('Roads may be slippery');
    }
    if (condition == WeatherCondition.fog) {
      advices.add('Reduced visibility - use lights');
    }
    if (windSpeed > 8) {
      advices.add('Strong winds - be cautious');
    }
    if (temperature < 5) {
      advices.add('Cold weather - dress warmly');
    }
    if (temperature > 30) {
      advices.add('Hot weather - stay hydrated');
    }
    if (humidity > 80 && temperature > 25) {
      advices.add('High humidity - take breaks');
    }

    return advices.isEmpty
        ? 'Good conditions for cycling!'
        : advices.join('. ');
  }

  factory WeatherData.fromOpenWeather(Map<String, dynamic> json) {
    final main = json['main'] as Map<String, dynamic>;
    final wind = json['wind'] as Map<String, dynamic>;
    final weatherList = json['weather'] as List<dynamic>;
    final weather = weatherList.isNotEmpty ? weatherList[0] : {};

    final weatherId = weather['id'] as int? ?? 800;
    final condition = _mapWeatherIdToCondition(weatherId);

    final alerts = <WeatherAlert>[];

    // Generate alerts based on conditions
    if (condition == WeatherCondition.rain ||
        condition == WeatherCondition.heavyRain) {
      alerts.add(
        WeatherAlert(
          title: 'Wet Roads',
          message: 'Roads may be slippery due to rain. Reduce speed on turns.',
          severity: condition == WeatherCondition.heavyRain
              ? AlertSeverity.warning
              : AlertSeverity.info,
          icon: '🌧️',
        ),
      );
    }

    if (condition == WeatherCondition.storm) {
      alerts.add(
        const WeatherAlert(
          title: 'Storm Warning',
          message: 'Dangerous conditions. Consider postponing your ride.',
          severity: AlertSeverity.danger,
          icon: '⛈️',
        ),
      );
    }

    final windSpeedMs = (wind['speed'] as num?)?.toDouble() ?? 0;
    if (windSpeedMs > 10) {
      alerts.add(
        WeatherAlert(
          title: 'Strong Winds',
          message:
              'Wind speed: ${(windSpeedMs * 3.6).toStringAsFixed(0)} km/h. Be careful on exposed routes.',
          severity: windSpeedMs > 15
              ? AlertSeverity.warning
              : AlertSeverity.info,
          icon: '💨',
        ),
      );
    }

    if (condition == WeatherCondition.fog) {
      alerts.add(
        const WeatherAlert(
          title: 'Low Visibility',
          message: 'Foggy conditions. Use front and rear lights.',
          severity: AlertSeverity.warning,
          icon: '🌫️',
        ),
      );
    }

    return WeatherData(
      temperature: (main['temp'] as num?)?.toDouble() ?? 20,
      humidity: (main['humidity'] as num?)?.toDouble() ?? 50,
      windSpeed: windSpeedMs,
      condition: condition,
      description: weather['description']?.toString() ?? 'Unknown',
      timestamp: DateTime.now(),
      alerts: alerts,
    );
  }

  static WeatherCondition _mapWeatherIdToCondition(int id) {
    // OpenWeatherMap condition codes
    if (id >= 200 && id < 300) return WeatherCondition.storm; // Thunderstorm
    if (id >= 300 && id < 400) return WeatherCondition.rain; // Drizzle
    if (id >= 500 && id < 505) return WeatherCondition.rain; // Light rain
    if (id >= 505 && id < 600) return WeatherCondition.heavyRain; // Heavy rain
    if (id >= 600 && id < 700) return WeatherCondition.snow; // Snow
    if (id >= 700 && id < 800)
      return WeatherCondition.fog; // Atmosphere (fog, mist)
    if (id == 800) return WeatherCondition.clear; // Clear
    if (id > 800 && id < 805) return WeatherCondition.cloudy; // Clouds
    return WeatherCondition.clear;
  }
}

/// Individual weather alert
class WeatherAlert {
  final String title;
  final String message;
  final AlertSeverity severity;
  final String icon;

  const WeatherAlert({
    required this.title,
    required this.message,
    required this.severity,
    required this.icon,
  });
}

/// Service to fetch weather data
class WeatherService {
  // Using OpenWeatherMap free tier
  // Get your free API key at: https://openweathermap.org/api
  // For production, store this securely (e.g., in environment variables)
  static const String _apiKey = '';
  static const String _baseUrl = '';

  WeatherData? _cachedWeather;
  DateTime? _lastFetch;
  static const Duration _cacheValidity = Duration(minutes: 15);

  /// Fetch weather for a location
  Future<WeatherData?> getWeather(double lat, double lon) async {
    // Return cached data if still valid
    if (_cachedWeather != null && _lastFetch != null) {
      if (DateTime.now().difference(_lastFetch!) < _cacheValidity) {
        return _cachedWeather;
      }
    }

    // If no API key, return mock data for demo
    if (_apiKey.isEmpty) {
      return _getMockWeather();
    }

    try {
      final url = Uri.parse(
        '$_baseUrl/weather?lat=$lat&lon=$lon&appid=$_apiKey&units=metric',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _cachedWeather = WeatherData.fromOpenWeather(json);
        _lastFetch = DateTime.now();
        return _cachedWeather;
      } else {
        debugPrint('Weather API error: ${response.statusCode}');
        return _getMockWeather();
      }
    } catch (e) {
      debugPrint('Weather fetch error: $e');
      return _getMockWeather();
    }
  }

  /// Get mock weather data for demo/testing
  WeatherData _getMockWeather() {
    // Simulate realistic Milan weather
    final hour = DateTime.now().hour;
    final isNight = hour < 6 || hour > 20;

    return WeatherData(
      temperature: isNight ? 12 : 18,
      humidity: 65,
      windSpeed: 3.5,
      condition: WeatherCondition.cloudy,
      description: isNight ? 'Partly cloudy' : 'Scattered clouds',
      timestamp: DateTime.now(),
      alerts: const [
        WeatherAlert(
          title: 'Good Cycling Weather',
          message: 'Conditions are favorable for cycling today.',
          severity: AlertSeverity.info,
          icon: '🚴',
        ),
      ],
    );
  }

  /// Get weather icon based on condition
  static String getWeatherIcon(WeatherCondition condition) {
    switch (condition) {
      case WeatherCondition.clear:
        return '☀️';
      case WeatherCondition.cloudy:
        return '☁️';
      case WeatherCondition.rain:
        return '🌧️';
      case WeatherCondition.heavyRain:
        return '⛈️';
      case WeatherCondition.snow:
        return '❄️';
      case WeatherCondition.fog:
        return '🌫️';
      case WeatherCondition.wind:
        return '💨';
      case WeatherCondition.storm:
        return '🌩️';
    }
  }
}
