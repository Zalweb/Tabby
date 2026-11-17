// Generated metadata from unchanged QA-033 PNG sheets; see frame-manifest.json.
import 'package:flutter/widgets.dart';

class MascotFrameSheet {
  const MascotFrameSheet(
    this.asset,
    this.sources, {
    this.wave = false,
    this.finite = false,
  });
  final String asset;
  final List<Rect> sources;
  final bool wave;
  final bool finite;

  /// Quiet holds separate short articulated clips. Celebration runs once.
  List<({int frame, int milliseconds})> get steps => finite
      ? const [
          (frame: 0, milliseconds: 120),
          (frame: 9, milliseconds: 120),
          (frame: 8, milliseconds: 100),
          (frame: 11, milliseconds: 120),
          (frame: 8, milliseconds: 100),
          (frame: 1, milliseconds: 75),
          (frame: 2, milliseconds: 90),
          (frame: 3, milliseconds: 75),
          (frame: 0, milliseconds: 200),
        ]
      : [
          const (frame: 0, milliseconds: 3200),
          const (frame: 1, milliseconds: 70),
          const (frame: 2, milliseconds: 80),
          const (frame: 3, milliseconds: 70),
          const (frame: 0, milliseconds: 1400),
          const (frame: 4, milliseconds: 100),
          const (frame: 5, milliseconds: 150),
          const (frame: 4, milliseconds: 100),
          const (frame: 7, milliseconds: 150),
          const (frame: 4, milliseconds: 100),
          const (frame: 0, milliseconds: 2600),
          if (wave) ...const [
            (frame: 8, milliseconds: 90),
            (frame: 9, milliseconds: 140),
            (frame: 8, milliseconds: 90),
            (frame: 11, milliseconds: 140),
            (frame: 8, milliseconds: 90),
            (frame: 0, milliseconds: 1800),
          ],
        ];
}

const mascotFrameSheets = <String, MascotFrameSheet>{
  'thinking': MascotFrameSheet(
    'assets/branding/mascot/tabby-thinking-frames-v1.png',
    [
      Rect.fromLTWH(0.044536923, 0.032694476, 0.169109357, 0.399098083),
      Rect.fromLTWH(0.294592846, 0.032694476, 0.169109357, 0.399098083),
      Rect.fromLTWH(0.544553852, 0.032694476, 0.169109357, 0.399098083),
      Rect.fromLTWH(0.794659760, 0.032694476, 0.169109357, 0.399098083),
      Rect.fromLTWH(0.044295431, 0.533258174, 0.169109357, 0.399098083),
      Rect.fromLTWH(0.294596330, 0.533258174, 0.169109357, 0.399098083),
      Rect.fromLTWH(0.544605952, 0.533258174, 0.169109357, 0.399098083),
      Rect.fromLTWH(0.794529327, 0.532130778, 0.169109357, 0.399098083),
    ],
    wave: false,
    finite: false,
  ),
  'waiting': MascotFrameSheet(
    'assets/branding/mascot/tabby-waiting-frames-v1.png',
    [
      Rect.fromLTWH(0.026342483, 0.021420519, 0.204058625, 0.438556933),
      Rect.fromLTWH(0.276363650, 0.021420519, 0.204058625, 0.438556933),
      Rect.fromLTWH(0.526683513, 0.021420519, 0.204058625, 0.438556933),
      Rect.fromLTWH(0.776365805, 0.021420519, 0.204058625, 0.438556933),
      Rect.fromLTWH(0.026084681, 0.521984216, 0.204058625, 0.438556933),
      Rect.fromLTWH(0.276210915, 0.521984216, 0.204058625, 0.438556933),
      Rect.fromLTWH(0.526419012, 0.521984216, 0.204058625, 0.438556933),
      Rect.fromLTWH(0.776124275, 0.521984216, 0.204058625, 0.438556933),
    ],
    wave: false,
    finite: false,
  ),
  'helpful': MascotFrameSheet(
    'assets/branding/mascot/tabby-helpful-frames-v1.png',
    [
      Rect.fromLTWH(0.037381805, 0.011970534, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.287459161, 0.011970534, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.537517085, 0.011970534, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.787436395, 0.011970534, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.037644064, 0.344383057, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.287952798, 0.344383057, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.537780069, 0.344383057, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.787841285, 0.344383057, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.037511095, 0.678637201, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.287771306, 0.678637201, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.537750613, 0.678637201, 0.182320442, 0.284530387),
      Rect.fromLTWH(0.787864056, 0.678637201, 0.182320442, 0.284530387),
    ],
    wave: true,
    finite: false,
  ),
  'reminder': MascotFrameSheet(
    'assets/branding/mascot/tabby-reminder-frames-v1.png',
    [
      Rect.fromLTWH(0.036393015, 0.015653775, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.285990776, 0.015653775, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.536095951, 0.015653775, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.785964618, 0.015653775, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.036427550, 0.348987109, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.286354026, 0.348987109, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.536330327, 0.348987109, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.786367567, 0.348987109, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.036176064, 0.682320442, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.286251168, 0.682320442, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.536134637, 0.682320442, 0.194751381, 0.281767956),
      Rect.fromLTWH(0.786331671, 0.682320442, 0.194751381, 0.281767956),
    ],
    wave: true,
    finite: false,
  ),
  'celebrating': MascotFrameSheet(
    'assets/branding/mascot/tabby-celebrating-frames-v1.png',
    [
      Rect.fromLTWH(0.022628144, 0.009208103, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.272899367, 0.009208103, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.522743355, 0.009208103, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.772873762, 0.009208103, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.022906618, 0.343462247, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.272740660, 0.343462247, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.522882737, 0.343462247, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.772978938, 0.343462247, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.022898375, 0.675874770, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.273101857, 0.675874770, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.522849191, 0.675874770, 0.200966851, 0.291896869),
      Rect.fromLTWH(0.772786698, 0.675874770, 0.200966851, 0.291896869),
    ],
    wave: true,
    finite: true,
  ),
};
