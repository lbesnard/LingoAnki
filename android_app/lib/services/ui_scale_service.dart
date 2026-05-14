import 'package:flutter/material.dart';

class UiScaleService extends ChangeNotifier {
  static final UiScaleService _instance = UiScaleService._internal();
  factory UiScaleService() => _instance;
  UiScaleService._internal();

  double _scaleFactor = 1.0;
  double get scaleFactor => _scaleFactor;

  // Base design dimensions - minimum comfortable size
  static const double baseWidth = 360.0;  // Minimum mobile width
  static const double baseHeight = 640.0; // Minimum mobile height
  static const double minScale = 0.8;
  static const double maxScale = 1.5;

  void updateScale(Size screenSize) {
    // For now, let's use a more conservative approach
    // Only scale text, not the entire layout
    double newScale = 1.0;
    
    // Scale up text on larger screens
    if (screenSize.width > 600) {
      newScale = 1.1;
    }
    if (screenSize.width > 900) {
      newScale = 1.2;
    }
    if (screenSize.width > 1200) {
      newScale = 1.3;
    }
    
    // Scale down on very small screens
    if (screenSize.width < 360) {
      newScale = screenSize.width / 360.0;
    }
    
    // Clamp to reasonable bounds
    newScale = newScale.clamp(minScale, maxScale);
    
    if ((newScale - _scaleFactor).abs() > 0.01) {
      _scaleFactor = newScale;
      notifyListeners();
    }
  }
}
