import 'package:rive_native/rive_native.dart' as rive;

/// Artboard painter driven by the editor timeline.
///
/// Unlike [rive.SingleAnimationPainter], playback time is owned by the
/// editor: the timeline can play, pause, scrub and loop, and the painter
/// reports time back through [onTimeChanged] every frame while playing.
base class TimelineAnimationPainter extends rive.BasicArtboardPainter {
  TimelineAnimationPainter({
    super.fit = rive.Fit.contain,
    super.alignment,
    this.onTimeChanged,
  });

  /// Invoked with the current animation time while playing.
  final void Function(double time)? onTimeChanged;

  rive.Animation? _animation;
  bool _playing = false;
  double _time = 0;

  double get time => _time;
  bool get isPlaying => _playing;
  double get duration => _animation?.duration ?? 0;

  /// Selects the animation to preview, or `null` to show the rest pose.
  void setAnimation(rive.Animation? animation) {
    _animation = animation;
    _time = 0;
    _applyAtCurrentTime();
    scheduleRepaint();
  }

  void play() {
    if (_animation == null) return;
    _playing = true;
    scheduleRepaint();
  }

  void pause() {
    _playing = false;
    scheduleRepaint();
  }

  /// Whether playback wraps around at the end of the animation.
  bool loop = true;

  /// Jumps to [seconds] on the timeline (used for scrubbing).
  void seek(double seconds) {
    _time = seconds.clamp(0, duration);
    _applyAtCurrentTime();
    scheduleRepaint();
  }

  void _applyAtCurrentTime() {
    final animation = _animation;
    if (animation == null) return;
    animation.time = _time;
    animation.apply();
    artboard?.advance(0);
  }

  @override
  bool advance(double elapsedSeconds) {
    final animation = _animation;
    if (animation == null || !_playing) {
      // Keep the artboard settled but let the ticker go idle.
      return super.advance(0);
    }

    _time += elapsedSeconds;
    if (_time >= duration) {
      if (loop) {
        _time = duration > 0 ? _time % duration : 0;
      } else {
        _time = duration;
        _playing = false;
      }
    }
    animation.time = _time;
    animation.apply();
    super.advance(elapsedSeconds);
    onTimeChanged?.call(_time);
    return _playing;
  }
}
