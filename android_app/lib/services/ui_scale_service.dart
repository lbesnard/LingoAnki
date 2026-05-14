import 'package:flutter/material.dart';

class UiScaleService extends ChangeNotifier {
  static final UiScaleService _instance = UiScaleService._internal();
  factory UiScaleService() => _instance;
  UiScaleService._internal();

  double _scaleFactor = 1.0;
  double get scaleFactor => _scaleFactor;

  // Base design dimensions (adjust based on your design)
  static const double baseWidth = 375.0;
  static const double baseHeight = 812.0;
  static const double minScale = 0.6;
  static const double maxScale = 2.0;

  void updateScale(Size screenSize) {
    // Calculate scale based on screen dimensions
    final widthScale = screenSize.width / baseWidth;
    final heightScale = screenSize.height / baseHeight;
    
    // Use the smaller scale to ensure content fits
    double newScale = (widthScale < heightScale) ? widthScale : heightScale;
    
    // Clamp to reasonable bounds
    newScale = newScale.clamp(minScale, maxScale);
    
    if (newScale != _scaleFactor) {
      _scaleFactor = newScale;
      notifyListeners();
    }
  }
}
