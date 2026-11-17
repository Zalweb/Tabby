import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tabby_mascot_frame_sheet.dart';

/// The supplied artwork has uneven transparent gutters, so use measured source
/// rectangles with an identical size and paw baseline rather than a grid split.
class TabbyMascotSprite extends StatefulWidget {
  final bool animate;
  final bool sleeping;
  final String asset;
  final Rect? normalizedSource;
  final int? decodeWidth;
  final MascotFrameSheet? frameSheet;
  final int? sheetDecodeWidth;

  const TabbyMascotSprite({
    super.key,
    required this.animate,
    this.sleeping = false,
    this.asset = 'assets/branding/tabby-blink-sheet.png',
    this.normalizedSource,
    this.decodeWidth,
    this.frameSheet,
    this.sheetDecodeWidth,
  });

  @override
  State<TabbyMascotSprite> createState() => _TabbyMascotSpriteState();
}

class _TabbyMascotSpriteState extends State<TabbyMascotSprite>
    with WidgetsBindingObserver {
  static const _holds = [3200, 80, 60, 65, 65, 60, 80, 190];
  ImageStream? _stream;
  late final ImageStreamListener _listener;
  ImageInfo? _image;
  ImageStream? _sheetStream;
  ImageInfo? _sheetImage;
  late final ImageStreamListener _sheetListener;
  bool _sheetFailed = false;
  bool _usingSheet = false;
  bool _finitePlayed = false;
  Timer? _timer;
  int _frame = 0;
  bool _active = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
        });
        _syncPlayback();
      },
      onError: (Object error, StackTrace? stack) {
        // Keep the fallback visible without an uncaught asset-loading exception.
        if (mounted) {
          setState(() {
            _image?.dispose();
            _image = null;
          });
          _syncPlayback();
        }
      },
    );
    _sheetListener = ImageStreamListener(
      (image, synchronousCall) {
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _sheetImage?.dispose();
          _sheetImage = image;
          _syncPlayback();
        });
      },
      onError: (Object error, StackTrace? stack) {
        if (!mounted) return;
        setState(() {
          _sheetFailed = true;
          _sheetImage?.dispose();
          _sheetImage = null;
          _syncPlayback();
        });
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
    _resolveSheet();
    _syncPlayback();
  }

  void _resolveSheet() {
    final sheet = widget.frameSheet;
    if (sheet == null ||
        _sheetFailed ||
        !widget.animate ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final stream = ResizeImage.resizeIfNeeded(
      widget.sheetDecodeWidth,
      null,
      AssetImage(sheet.asset),
    ).resolve(createLocalImageConfiguration(context));
    if (_sheetStream?.key == stream.key) return;
    _sheetStream?.removeListener(_sheetListener);
    _sheetStream = stream;
    stream.addListener(_sheetListener);
  }

  void _resolveImage() {
    final stream = ResizeImage.resizeIfNeeded(
      widget.decodeWidth,
      null,
      AssetImage(widget.asset),
    ).resolve(createLocalImageConfiguration(context));
    if (_stream?.key != stream.key) {
      _stream?.removeListener(_listener);
      _stream = stream;
      stream.addListener(_listener);
    }
  }

  @override
  void didUpdateWidget(TabbyMascotSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.asset != oldWidget.asset ||
        widget.decodeWidth != oldWidget.decodeWidth) {
      _resolveImage();
    }
    if (widget.frameSheet != oldWidget.frameSheet ||
        widget.sheetDecodeWidth != oldWidget.sheetDecodeWidth) {
      _sheetStream?.removeListener(_sheetListener);
      _sheetStream = null;
      _sheetImage?.dispose();
      _sheetImage = null;
      _sheetFailed = false;
      if (widget.frameSheet != oldWidget.frameSheet) _finitePlayed = false;
    }
    _resolveSheet();
    _syncPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    setState(_syncPlayback);
  }

  void _syncPlayback() {
    final useSheet = widget.frameSheet != null && _sheetImage != null;
    if (widget.frameSheet?.finite == true &&
        (!widget.animate ||
            !_foreground ||
            !TickerMode.valuesOf(context).enabled ||
            MediaQuery.disableAnimationsOf(context))) {
      _finitePlayed = true;
    }
    final allowed =
        widget.animate &&
        (widget.normalizedSource == null || useSheet) &&
        !widget.sleeping &&
        _image != null &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (allowed == _active && useSheet == _usingSheet) return;
    _active = allowed;
    _usingSheet = useSheet;
    _timer?.cancel();
    _timer = null;
    _frame = 0;
    if (allowed && !(useSheet && widget.frameSheet!.finite && _finitePlayed)) {
      if (useSheet && widget.frameSheet!.finite) _finitePlayed = true;
      _scheduleFrame();
    }
  }

  void _scheduleFrame() {
    // A single timer changes only the eight frames; the 3.2-second open-eye
    // hold does not continuously rebuild or repaint the sprite.
    final sheet = _usingSheet ? widget.frameSheet : null;
    final length = sheet?.steps.length ?? _holds.length;
    final hold = sheet?.steps[_frame].milliseconds ?? _holds[_frame];
    _timer = Timer(Duration(milliseconds: hold), () {
      if (!mounted || !_active) return;
      if (sheet?.finite == true && _frame == length - 1) {
        setState(() => _frame = 0);
        _timer = null;
        return;
      }
      setState(() => _frame = (_frame + 1) % length);
      _scheduleFrame();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _stream?.removeListener(_listener);
    _sheetStream?.removeListener(_sheetListener);
    _sheetImage?.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.frameSheet;
    final showSheet =
        _usingSheet &&
        widget.animate &&
        !MediaQuery.disableAnimationsOf(context);
    final image = showSheet ? _sheetImage?.image : _image?.image;
    final frame = showSheet
        ? sheet!.steps[_frame].frame
        : widget.sleeping
        ? 3
        : _frame;
    return ExcludeSemantics(
      child: image == null
          ? widget.normalizedSource == null
                ? const Center(child: Icon(Icons.pets_rounded))
                : const SizedBox.expand()
          : RepaintBoundary(
              child: CustomPaint(
                painter: TabbyMascotSpritePainter(
                  image: image,
                  frame: frame,
                  normalizedSource: showSheet
                      ? sheet!.sources[frame]
                      : widget.normalizedSource,
                ),
                size: Size.infinite,
              ),
            ),
    );
  }
}

class TabbyMascotSpritePainter extends CustomPainter {
  final ui.Image image;
  final int frame;
  final Rect? normalizedSource;

  const TabbyMascotSpritePainter({
    required this.image,
    required this.frame,
    this.normalizedSource,
  });

  static const _sources = [
    Rect.fromLTWH(32, 195, 268, 328),
    Rect.fromLTWH(345, 195, 268, 328),
    Rect.fromLTWH(659, 195, 268, 328),
    Rect.fromLTWH(972, 196, 268, 328),
    Rect.fromLTWH(32, 770, 268, 328),
    Rect.fromLTWH(345, 770, 268, 328),
    Rect.fromLTWH(659, 770, 268, 328),
    Rect.fromLTWH(972, 770, 268, 328),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final normalized = normalizedSource;
    final source = normalized == null
        ? _sources[frame]
        : Rect.fromLTWH(
            normalized.left * image.width,
            normalized.top * image.height,
            normalized.width * image.width,
            normalized.height * image.height,
          );
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final target = Alignment.bottomCenter.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      source,
      target,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(TabbyMascotSpritePainter oldDelegate) =>
      image != oldDelegate.image ||
      frame != oldDelegate.frame ||
      normalizedSource != oldDelegate.normalizedSource;
}
