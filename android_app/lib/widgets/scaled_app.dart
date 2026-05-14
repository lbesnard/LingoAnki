import 'package:flutter/material.dart';
import '../services/ui_scale_service.dart';

class ScaledApp extends StatefulWidget {
  final Widget child;
  
  const ScaledApp({Key? key, required this.child}) : super(key: key);

  @override
  State<ScaledApp> createState() => _ScaledAppState();
}

class _ScaledAppState extends State<ScaledApp> {
  final UiScaleService _scaleService = UiScaleService();

  @override
  void initState() {
    super.initState();
    _scaleService.addListener(_onScaleChanged);
  }

  @override
  void dispose() {
    _scaleService.removeListener(_onScaleChanged);
    super.dispose();
  }

  void _onScaleChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Update scale based on available space
        _scaleService.updateScale(Size(constraints.maxWidth, constraints.maxHeight));
        
        return Transform.scale(
          scale: _scaleService.scaleFactor,
          child: widget.child,
        );
      },
    );
  }
}
