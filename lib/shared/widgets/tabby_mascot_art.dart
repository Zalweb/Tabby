import 'package:flutter/material.dart';

import 'tabby_mascot_sprite.dart';
import 'tabby_mascot_frame_sheet.dart';

/// Presentation roles, independent of ledger/payment status.
enum TabbyMascotPose {
  neutral,
  welcome,
  notebook,
  thinking,
  waiting,
  reminder,
  celebrating,
  helpful,
  sleeping,
}

class MascotArtwork {
  const MascotArtwork(this.asset, this.normalizedSource);
  final String asset;
  final Rect? normalizedSource;
  static const specs = <TabbyMascotPose, MascotArtwork>{
    TabbyMascotPose.thinking: MascotArtwork(
      'assets/branding/mascot/tabby-thinking.png',
      Rect.fromLTWH(0.160287081, 0.084529506, 0.637958533, 0.835725678),
    ),
    TabbyMascotPose.waiting: MascotArtwork(
      'assets/branding/mascot/tabby-waiting.png',
      Rect.fromLTWH(0.171451356, 0.093301435, 0.619617225, 0.824561404),
    ),
    TabbyMascotPose.helpful: MascotArtwork(
      'assets/branding/mascot/tabby-helpful.png',
      Rect.fromLTWH(0.149920255, 0.071770335, 0.662679426, 0.869218501),
    ),
    TabbyMascotPose.reminder: MascotArtwork(
      'assets/branding/mascot/tabby-reminder.png',
      Rect.fromLTWH(0.161881978, 0.084529506, 0.633173844, 0.837320574),
    ),
    TabbyMascotPose.celebrating: MascotArtwork(
      'assets/branding/mascot/tabby-celebrating.png',
      Rect.fromLTWH(0.143540670, 0.074960128, 0.700956938, 0.862041467),
    ),
    TabbyMascotPose.welcome: MascotArtwork(
      'assets/branding/tabby-welcome-v3.png',
      Rect.fromLTWH(0.139553429, 0.086921850, 0.725677831, 0.859649123),
    ),
    TabbyMascotPose.notebook: MascotArtwork(
      'assets/branding/tabby-notebook-v3.png',
      Rect.fromLTWH(0.121212121, 0.071770335, 0.685007974, 0.887559809),
    ),
    TabbyMascotPose.neutral: MascotArtwork(
      'assets/branding/tabby-blink-sheet.png',
      null,
    ),
    TabbyMascotPose.sleeping: MascotArtwork(
      'assets/branding/tabby-blink-sheet.png',
      null,
    ),
  };
}

/// Normalized crop bounds remove unequal transparent gutters without changing
/// original pixels. All poses fit a common bottom-center presentation anchor.
class TabbyMascotArt extends StatelessWidget {
  const TabbyMascotArt({
    super.key,
    required this.pose,
    required this.animate,
    required this.size,
  });
  final TabbyMascotPose pose;
  final bool animate;
  final double size;
  @override
  Widget build(BuildContext context) {
    final spec = MascotArtwork.specs[pose]!;
    return TabbyMascotSprite(
      key: ValueKey('mascot-art-${pose.name}'),
      asset: spec.asset,
      normalizedSource: spec.normalizedSource,
      decodeWidth: spec.normalizedSource == null
          ? null
          : (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
              64,
              1024,
            ),
      animate: animate,
      sleeping: pose == TabbyMascotPose.sleeping,
      frameSheet: mascotFrameSheets[pose.name],
      sheetDecodeWidth: (size * MediaQuery.devicePixelRatioOf(context) * 4)
          .ceil()
          .clamp(256, 2048),
    );
  }
}
