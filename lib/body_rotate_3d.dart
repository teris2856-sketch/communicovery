import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/body_painter.dart';
import 'package:swiftspeak/body_side_profile_painter.dart';

/// Which face of the shallow 3D box best faces the camera (+Z), after [rotationY].
enum BodyBoxFace { front, back, sideLeft, sideRight }

/// Four faces around a shallow box — real [rotateY] in 3D (with perspective), not alpha cross-fading.
class BodyRotate3D extends StatelessWidget {
  /// Yaw (radians) around the vertical axis.
  final double rotationY;

  /// Content width / height matching front panel.
  final double width;
  final double height;

  /// Pain / hotspot layers in each face’s local coordinates (0–1 positions match the painters).
  final Widget? frontOverlay;
  final Widget? backOverlay;
  final Widget? sideLeftOverlay;
  final Widget? sideRightOverlay;

  const BodyRotate3D({
    super.key,
    required this.rotationY,
    required this.width,
    required this.height,
    this.frontOverlay,
    this.backOverlay,
    this.sideLeftOverlay,
    this.sideRightOverlay,
  });

  /// Canonical yaw angles (radians): front 0°, left side +90°, right side −90°, back 180°.
  static const double yawFront = 0;
  static const double yawBack = math.pi;
  static const double yawLeftSide = math.pi / 2;
  static const double yawRightSide = -math.pi / 2;

  static const List<double> _snapYaws = [
    yawFront,
    yawLeftSide,
    yawRightSide,
    yawBack,
  ];

  /// Snaps continuous drag rotation to the nearest cardinal view.
  static double snapRotationY(double rotationY) {
    var r = rotationY;
    while (r > math.pi) {
      r -= 2 * math.pi;
    }
    while (r < -math.pi) {
      r += 2 * math.pi;
    }
    var best = _snapYaws.first;
    var bestDist = (r - best).abs();
    for (final snap in _snapYaws.skip(1)) {
      final d = (r - snap).abs();
      if (d < bestDist) {
        bestDist = d;
        best = snap;
      }
    }
    return best;
  }

  /// Human-readable label for the view facing the camera.
  static String viewLabelForFace(BodyBoxFace face) {
    final t = AppLanguage.instance.t;
    switch (face) {
      case BodyBoxFace.front:
        return t('viewFront');
      case BodyBoxFace.back:
        return t('viewBack');
      case BodyBoxFace.sideLeft:
        return t('viewLeft');
      case BodyBoxFace.sideRight:
        return t('viewRight');
    }
  }

  /// World +Z is toward the viewer; largest Z component of the face outward normal wins.
  static BodyBoxFace dominantFaceTowardCamera(double rotationY) {
    final c = math.cos(rotationY);
    final s = math.sin(rotationY);
    const order = [
      BodyBoxFace.front,
      BodyBoxFace.back,
      BodyBoxFace.sideLeft,
      BodyBoxFace.sideRight,
    ];
    final scores = [c, -c, s, -s];
    var bestI = 0;
    for (var i = 1; i < 4; i++) {
      if (scores[i] > scores[bestI] + 1e-5) {
        bestI = i;
      }
    }
    return order[bestI];
  }

  static const double _perspective = 0.00118;

  /// Half-depth of the 3D box (must match marker horizontal inset in `BodyCheck`).
  static double depthZ(double bodyWidth) =>
      math.max(16.0, bodyWidth * 0.086);

  /// Width of each lateral face — wide enough for side markers after layout compresses the figure.
  static double sidePanelWidth(double bodyWidth) {
    final z = depthZ(bodyWidth);
    return math.max(z * 2.15, math.max(48.0, bodyWidth * 0.32));
  }

  static Widget _faceStack(CustomPainter painter, Widget? overlay) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: CustomPaint(painter: painter),
          ),
        ),
        if (overlay != null) Positioned.fill(child: overlay),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final z = depthZ(width);
    final sideW = sidePanelWidth(width);

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, _perspective)
        ..rotateY(rotationY),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.translationValues(0, 0, z),
              child: SizedBox(
                width: width,
                height: height,
                child: _faceStack(
                  const BodyFacingPainter(isBack: false),
                  frontOverlay,
                ),
              ),
            ),
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.translationValues(0, 0, -z) *
                  Matrix4.rotationY(math.pi),
              child: SizedBox(
                width: width,
                height: height,
                child: _faceStack(
                  const BodyFacingPainter(isBack: true),
                  backOverlay,
                ),
              ),
            ),
            // Side faces have no overlay today. If they still hit-test, their wide rotated
            // rects steal events from front/back (stack tests sides before front) — breaks
            // rotation and marker taps. When a side overlay exists, allow hits again.
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.translationValues(z, 0, 0) *
                  Matrix4.rotationY(-math.pi / 2),
              child: IgnorePointer(
                ignoring: sideLeftOverlay == null,
                child: SizedBox(
                  width: sideW,
                  height: height,
                  child: _faceStack(
                    const BodySideProfilePainter(mirror: false),
                    sideLeftOverlay,
                  ),
                ),
              ),
            ),
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.translationValues(-z, 0, 0) *
                  Matrix4.rotationY(math.pi / 2),
              child: IgnorePointer(
                ignoring: sideRightOverlay == null,
                child: SizedBox(
                  width: sideW,
                  height: height,
                  child: _faceStack(
                    const BodySideProfilePainter(mirror: true),
                    sideRightOverlay,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
