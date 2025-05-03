// app_config.dart - Global app configuration

class AppConfig {
  // Authentication settings
  static bool enableOtpVerification = true; // Set to true to enable OTP verification
  
  // App settings
  static const String appName = "Bus Tracker";
  static const String appVersion = "1.0.0";
  
  // Firebase collections
  static const String usersCollection = "users";
  
  // Default settings
  static const bool enableNotifications = true;
  static const bool enableLocationTracking = true;
  
  // Timeouts (in seconds)
  static const int otpTimeoutSeconds = 60;
  static const int locationUpdateIntervalSeconds = 30;
  
  // Map settings
  static const double defaultMapZoom = 15.0;
} 