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
  static const double minScale = 0.7;
  static const double maxScale = 3.0;

  void updateScale(Size screenSize) {
    // Calculate scale factors for width and height independently
    final widthScale = screenSize.width / baseWidth;
    final heightScale = screenSize.height / baseHeight;
    
    // Use the smaller scale to ensure everything fits, but don't go below 1.0 unless necessary
    double newScale = (widthScale < heightScale) ? widthScale : heightScale;
    
    // Only scale down if the screen is smaller than base dimensions
    if (screenSize.width >= baseWidth && screenSize.height >= baseHeight) {
      // For larger screens, use a more moderate scaling approach
      newScale = 1.0 + (newScale - 1.0) * 0.5; // Scale up more gradually
    }
    
    // Clamp to reasonable bounds
    newScale = newScale.clamp(minScale, maxScale);
    
    if ((newScale - _scaleFactor).abs() > 0.01) {
      _scaleFactor = newScale;
      notifyListeners();
    }
  }
}
