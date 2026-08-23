import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../engine/coach_cue.dart';
import 'coach_voice.dart';
import 'coach_voice_selection.dart';
import 'debug_log.dart';

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
      await _tts.setLanguage(_language);
      // Upgrade off the (often robotic) default voice to the most natural
      // neural / enhanced voice the phone actually has installed. Best-effort:
      // if none is clearly better, we leave the default alone.
      await _selectNaturalVoice();
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

  /// The coach speaks British English. Used for both the language and to prefer
  /// a matching-accent voice.
  static const String _language = 'en-GB';

  /// Enumerate the installed voices and switch to the most natural English one.
  /// Wrapped so a phone that can't list voices simply keeps the default voice.
  Future<void> _selectNaturalVoice() async {
    try {
      final voices = _readVoices(await _tts.getVoices);
      final best = pickBestVoice(voices, preferredLocale: _language);
      if (best == null) {
        DebugLog.instance.log(
          'no upgraded voice found — keeping OS default',
          tag: 'voice',
        );
        return;
      }
      await _tts.setVoice(<String, String>{
        'name': best['name']!,
        'locale': best['locale']!,
      });
      DebugLog.instance
          .log('voice → ${best['name']} (${best['locale']})', tag: 'voice');
    } on Object catch (error) {
      debugPrint('Voice selection failed: $error');
    }
  }

  /// Normalise `getVoices` output (a list of platform maps with dynamic keys /
  /// values) into `{name, locale, quality?, identifier?}` string maps.
  static List<Map<String, String>> _readVoices(Object? raw) {
    if (raw is! List) return const <Map<String, String>>[];
    final out = <Map<String, String>>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final voice = <String, String>{};
      entry.forEach((key, value) {
        if (key != null && value != null) {
          voice[key.toString()] = value.toString();
        }
      });
      if (voice['name'] != null && voice['locale'] != null) out.add(voice);
    }
    return out;
  }

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
