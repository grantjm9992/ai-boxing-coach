import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../engine/coach_cue.dart';
import 'coach_voice.dart';

/// The real coach voice: device text-to-speech for the words, bundled one-shot
/// samples for the bells.
///
/// The spec's open question 3 recommends TTS for v1 and revisiting a recorded
/// voice later. Device TTS costs nothing, needs no network, and means the cue
/// scripts can change without re-recording anything — the right trade for a
/// proof of concept whose job is to find out whether the coaching UX works.
///
/// English only in v0.1, per the MVP scope.
class DeviceCoachVoice implements CoachVoice {
  DeviceCoachVoice({FlutterTts? tts, AudioPlayer? player})
    : _tts = tts ?? FlutterTts(),
      _player = player ?? AudioPlayer(playerId: 'coach_cues');

  final FlutterTts _tts;
  final AudioPlayer _player;

  bool _ready = false;
  bool _speaking = false;

  /// Prepares the engine. Safe to call more than once.
  Future<void> initialise() async {
    if (_ready) return;
    _ready = true;
    try {
      await _tts.setLanguage('en-GB');
      await _tts.setSpeechRate(_speechRate);
      await _tts.setVolume(1);
      await _tts.setPitch(1);
      await _tts.awaitSpeakCompletion(true);
      // Mix with whatever the athlete is already listening to rather than
      // stopping it: people train to music, and a coach that kills the track
      // for every cue gets muted within one session.
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        <IosTextToSpeechAudioCategoryOptions>[
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            options: const <AVAudioSessionOptions>{
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.duckOthers,
            },
          ),
        ),
      );
    } on Object catch (error, stack) {
      // A phone without a TTS engine or without the assets should still get a
      // working timer; it just loses the voice.
      debugPrint('Coach voice unavailable: $error\n$stack');
    }
  }

  /// Slightly slower than default: cues are heard over exertion and breathing.
  static const double _speechRate = 0.5;

  @override
  Future<void> speak(String text, CuePriority priority) async {
    await initialise();
    if (_speaking) {
      switch (priority) {
        case CuePriority.critical:
          await _tts.stop();
        case CuePriority.important:
          await _tts.stop();
        case CuePriority.routine:
          // The coach does not talk over itself for a routine reminder.
          return;
      }
    }
    _speaking = true;
    try {
      await _tts.speak(text);
    } on Object catch (error) {
      debugPrint('Coach voice failed to speak: $error');
    } finally {
      _speaking = false;
    }
  }

  @override
  Future<void> playSound(CueSound sound) async {
    await initialise();
    try {
      await _player.stop();
      await _player.play(AssetSource(sound.assetPath));
    } on Object catch (error) {
      debugPrint('Coach cue sound failed: $error');
    }
  }

  @override
  Future<void> silence() async {
    _speaking = false;
    try {
      await _tts.stop();
      await _player.stop();
    } on Object catch (error) {
      debugPrint('Coach voice failed to stop: $error');
    }
  }

  @override
  Future<void> dispose() async {
    await silence();
    await _player.dispose();
  }
}
