import 'package:flutter/material.dart';

class UiScaleService extends ChangeNotifier {
  static final UiScaleService _instance = UiScaleService._internal();
  factory UiScaleService() => _instance;
  UiScaleService._internal();

  double _scaleFactor = 1.0;
  double get scaleFactor => _scaleFactor;

  // Base design dimensions - use more web-friendly dimensions
  static const double baseWidth = 1200.0;
  static const double baseHeight = 800.0;
  static const double minScale = 0.5;
  static const double maxScale = 2.0;

  void updateScale(Size screenSize) {
    // For web, we want to be more conservative with scaling
    // Only scale down if the screen is significantly smaller
    double newScale = 1.0;
    
    if (screenSize.width < baseWidth || screenSize.height < baseHeight) {
      final widthScale = screenSize.width / baseWidth;
      final heightScale = screenSize.height / baseHeight;
      newScale = (widthScale < heightScale) ? widthScale : heightScale;
    }
    
    // Clamp to reasonable bounds
    newScale = newScale.clamp(minScale, maxScale);
    
    if ((newScale - _scaleFactor).abs() > 0.01) {
      _scaleFactor = newScale;
      notifyListeners();
    }
  }
}
