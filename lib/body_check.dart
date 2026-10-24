import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/body_check_history.dart';
import 'package:swiftspeak/body_check_results.dart';
import 'package:swiftspeak/body_check_service.dart';
import 'package:swiftspeak/body_anatomy_anchors.dart';
import 'package:swiftspeak/body_glb_viewer.dart';
import 'package:swiftspeak/body_rotate_3d.dart';

enum PainLevel {
  none,
  low,
  moderate,
  high,
}

class BodyCheck extends StatefulWidget {
  const BodyCheck({super.key});

  @override
  State<BodyCheck> createState() => _BodyCheckState();
}

class _BodyCheckState extends State<BodyCheck> {
  final Map<String, PainLevel> _frontPainLevels = {};
  final Map<String, PainLevel> _backPainLevels = {};
  final Map<String, PainLevel> _sidePainLevels = {};
  final BodyCheckService _service = BodyCheckService();

  /// Yaw (radians) around vertical axis — horizontal drag only.
  double _rotationY = 0;

  Map<String, PainLevel> _levelsForAnchor(String id) {
    if (BodyAnatomyProjection.isSideId(id)) return _sidePainLevels;
    if (BodyAnatomyProjection.isBackId(id)) return _backPainLevels;
    return _frontPainLevels;
  }

  static String _spotLabel(String id) {
    final lang = AppLanguage.instance;
    if (id == 'spot9') return lang.t('bodyLowerAbdomen');
    if (id == 'LeftHip' || id == 'RightHip') {
      return lang.t(id == 'LeftHip' ? 'bodyLeftHip' : 'bodyRightHip');
    }
    if (id == 'LeftElbow' || id == 'RightElbow') {
      return lang.t(id == 'LeftElbow' ? 'bodyLeftElbow' : 'bodyRightElbow');
    }
    if (id == 'LeftHand' || id == 'RightHand') {
      return lang.t(id == 'LeftHand' ? 'bodyLeftHand' : 'bodyRightHand');
    }
    if (id.endsWith('Palm')) {
      return id.contains('Left') ? lang.t('bodyLeftHand') : lang.t('bodyRightHand');
    }
    return lang.bodyPartLabel(id);
  }

  void _cyclePainLevel(String id, Map<String, PainLevel> levels) {
    final current = levels[id] ?? PainLevel.none;
    switch (current) {
      case PainLevel.none:
        levels[id] = PainLevel.low;
        break;
      case PainLevel.low:
        levels[id] = PainLevel.moderate;
        break;
      case PainLevel.moderate:
        levels[id] = PainLevel.high;
        break;
      case PainLevel.high:
        levels[id] = PainLevel.none;
        break;
    }
  }

  // Convert enum to int (0-3) for Firebase-friendly storage
  int _toInt(PainLevel level) {
    switch (level) {
      case PainLevel.none:
        return 0;
      case PainLevel.low:
        return 1;
      case PainLevel.moderate:
        return 2;
      case PainLevel.high:
        return 3;
    }
  }

  Map<String, int> _painToPayload(Map<String, PainLevel> source) {
    final out = <String, int>{};
    source.forEach((key, value) {
      final v = _toInt(value);
      if (v > 0) out[key] = v;
    });
    return out;
  }

  // Get color for a given pain level
  Color _colorForPain(PainLevel level) {
    switch (level) {
      case PainLevel.low:
        return Colors.green;
      case PainLevel.moderate:
        return Colors.yellow;
      case PainLevel.high:
        return Colors.red;
      case PainLevel.none:
        return const Color(0xFF4A5F70);
    }
  }

  Widget _buildFacePainButton(
    String id,
    Offset normalizedPosition,
    double w,
    double h,
    Map<String, PainLevel> levels, {
    double halfExtent = 17,
    bool showTooltip = false,
  }) {
    final level = levels[id] ?? PainLevel.none;
    final d = halfExtent * 2;
    final iconSize = (halfExtent * 0.94).clamp(12.0, 16.0);
    Widget markerVisual = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: _colorForPain(level).withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(
          color: level == PainLevel.none ? Colors.white70 : Colors.white,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _colorForPain(level).withValues(alpha: 0.35),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Icon(
        level == PainLevel.none ? Icons.add : Icons.check,
        size: iconSize,
        color: Colors.white,
      ),
    );
    if (showTooltip) {
      markerVisual = Tooltip(
        message: _spotLabel(id),
        waitDuration: const Duration(milliseconds: 400),
        child: markerVisual,
      );
    }
    return Positioned(
      left: normalizedPosition.dx * w - halfExtent,
      top: normalizedPosition.dy * h - halfExtent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _cyclePainLevel(id, levels);
          });
        },
        child: Semantics(
          label: '${_spotLabel(id)} pain marker',
          button: true,
          child: markerVisual,
        ),
      ),
    );
  }

  Widget _rotatingPainMarkersLayer({
    required double rotationY,
    required double viewportShortSide,
    bool showTooltips = false,
  }) {
    final markerHalfExtent =
        (viewportShortSide * 0.038).clamp(12.0, 15.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final markers = <Widget>[];

        final anchors =
            BodyAnatomyProjection.anchorsForRotation(rotationY);
        for (final anchor in anchors) {
          final projected = BodyAnatomyProjection.project(anchor, rotationY);
          if (projected == null) continue;
          markers.add(
            _buildFacePainButton(
              anchor.id,
              projected,
              w,
              h,
              _levelsForAnchor(anchor.id),
              halfExtent: markerHalfExtent,
              showTooltip: showTooltips,
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: markers,
        );
      },
    );
  }

  Future<void> _submit() async {
    final frontPayload = _painToPayload(_frontPainLevels);
    final backPayload = _painToPayload(_backPainLevels);
    final sidePayload = _painToPayload(_sidePainLevels);
    try {
      final entryId = await _service.createEntry(
        frontPain: frontPayload,
        backPain: backPayload,
        sidePain: sidePayload,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BodyCheckResults(entryId: entryId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLanguage.instance.t('failedSubmitBody', {'error': '$e'}))),
      );
    }
  }

  static const _cardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.all(Radius.circular(24)),
    boxShadow: [
      BoxShadow(
        color: Color(0x0F000000),
        blurRadius: 18,
        offset: Offset(0, 8),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return AppLangBuilder(
      builder: (context, t) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: Text(t('bodyCheck')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BodyCheckHistory()),
              );
            },
            child: Text(
              t('history'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  t('bodyCheckHelp'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Container(
                    width: 360,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    decoration: _cardDecoration,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const aspect = 0.86;
                        const fill = 0.99;
                        final maxW = constraints.maxWidth;
                        final maxH = constraints.maxHeight;

                        double figW = maxW * fill;
                        double figH = figW / aspect;
                        if (figH > maxH * fill) {
                          figH = maxH * fill;
                          figW = figH * aspect;
                        }

                        var scale = 1.0;
                        if (figH < maxH * fill) {
                          scale = math.min(
                            (maxH * fill) / figH,
                            1.22,
                          );
                        }

                        final face =
                        BodyRotate3D.dominantFaceTowardCamera(
                          _rotationY,
                        );
                        final viewLabel =
                        BodyRotate3D.viewLabelForFace(face);

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            clipBehavior: Clip.none,
                            children: [
                              const Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0xFF121E36),
                                  ),
                                ),
                              ),
                              Center(
                                child: Transform.scale(
                                  scale: scale,
                                  child: SizedBox(
                                    width: figW,
                                    height: figH,
                                    child: BodyGlbViewer(
                                      rotationY: _rotationY,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: Listener(
                                  behavior: HitTestBehavior.translucent,
                                  onPointerMove: (e) {
                                    if (!e.down) return;
                                    setState(() {
                                      _rotationY += e.delta.dx * 0.0065;
                                    });
                                  },
                                  onPointerUp: (_) {
                                    setState(() {
                                      _rotationY = BodyRotate3D.snapRotationY(
                                        _rotationY,
                                      );
                                    });
                                  },
                                  onPointerCancel: (_) {
                                    setState(() {
                                      _rotationY = BodyRotate3D.snapRotationY(
                                        _rotationY,
                                      );
                                    });
                                  },
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Center(
                                child: Transform.scale(
                                  scale: scale,
                                  child: SizedBox(
                                    width: figW,
                                    height: figH,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      clipBehavior: Clip.none,
                                      children: [
                                        _rotatingPainMarkersLayer(
                                          rotationY: _rotationY,
                                          viewportShortSide: math.min(figW, figH),
                                          showTooltips: true,
                                        ),
                                        Positioned(
                                          top: -22,
                                          left: 0,
                                          right: 0,
                                          child: Text(
                                            viewLabel,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Color(0xFFE8FDFF),
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 6,
                                child: Text(
                                  t('dragToRotate'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(1.0),
                          child: Text(
                            t('painLevel'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircleAvatar(
                              radius: 10,
                              backgroundImage: NetworkImage(
                                "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRISgUY1LYyDbI6iMh6s2JuDGdewgUgYSs9Ag&s",
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(t('painLow')),
                            ),
                            const CircleAvatar(
                              radius: 10,
                              backgroundImage: NetworkImage(
                                "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQNpQQIlRMWZLe4IuUKjstO0pVXmvCLP8A3lg&s",
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(t('painModerate')),
                            ),
                            const CircleAvatar(
                              radius: 10,
                              backgroundImage: NetworkImage(
                                "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRZwznd8328FB3mHv3HorzAnwKy6w0KxXjREg&s",
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(t('painHigh')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: Text(
                        t('submit'),
                        style: const TextStyle(fontSize: 18.0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}