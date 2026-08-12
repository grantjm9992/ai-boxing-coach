import 'package:flutter/material.dart';

import '../../analysis/drill.dart';
import '../../analysis/landmarks.dart';
import '../../analysis/school.dart';
import '../../domain/user_profile.dart';
import '../../services/profile_store.dart';
import '../theme.dart';

/// Pick the athlete's stance, guard style and the school they're training
/// toward. This is what turns the (fully-ported) style/school coaching on: every
/// technical round is analysed against the profile chosen here.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({this.store, super.key});

  final ProfileStore? store;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileStore _store = widget.store ?? const ProfileStore();
  UserProfile _profile = const UserProfile();
  bool _loaded = false;

  static const Map<Style, String> _styleLabels = <Style, String>{
    Style.highGuard: 'High guard',
    Style.phillyShell: 'Philly shell',
    Style.peekABoo: 'Peek-a-boo',
    Style.outBoxer: 'Out-boxer',
  };

  static const Map<Style, String> _styleBlurbs = <Style, String>{
    Style.highGuard: 'Textbook hands-up guard. Every check at its default.',
    Style.phillyShell: 'Lead hand low across the body — guard checks judge the rear hand only.',
    Style.peekABoo: 'Hands by the cheeks, constant head movement — held to a higher head bar.',
    Style.outBoxer: 'Range and footwork over slips — head-movement off, footwork bar raised.',
  };

  static const Map<School?, String> _schoolLabels = <School?, String>{
    null: 'None',
    School.soviet: 'Soviet',
    School.mexican: 'Mexican',
    School.european: 'European',
    School.american: 'American',
  };

  @override
  void initState() {
    super.initState();
    _store.load().then((profile) {
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loaded = true;
      });
    });
  }

  void _update(UserProfile next) {
    setState(() => _profile = next);
    _store.save(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                const Text(
                  'Rounds are coached against this. Change it and the next '
                  'round is judged in that game.',
                  style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 24),
                const _Label('Stance'),
                const SizedBox(height: 8),
                SegmentedButton<Stance>(
                  segments: const <ButtonSegment<Stance>>[
                    ButtonSegment<Stance>(
                      value: Stance.orthodox,
                      label: Text('Orthodox'),
                    ),
                    ButtonSegment<Stance>(
                      value: Stance.southpaw,
                      label: Text('Southpaw'),
                    ),
                  ],
                  selected: <Stance>{_profile.stance},
                  onSelectionChanged: (s) =>
                      _update(_profile.copyWith(stance: s.first)),
                ),
                const SizedBox(height: 24),
                const _Label('Guard style'),
                const SizedBox(height: 8),
                for (final style in Style.values)
                  _StyleTile(
                    label: _styleLabels[style]!,
                    blurb: _styleBlurbs[style]!,
                    selected: _profile.style == style,
                    onTap: () => _update(_profile.copyWith(style: style)),
                  ),
                const SizedBox(height: 16),
                const _Label('School to coach toward'),
                const SizedBox(height: 4),
                const Text(
                  'Optional. Adds tactical nudges toward that national game.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final entry in _schoolLabels.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _profile.school == entry.key,
                        onSelected: (_) => _update(
                          entry.key == null
                              ? _profile.copyWith(clearSchool: true)
                              : _profile.copyWith(school: entry.key),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.label,
    required this.blurb,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppTheme.surfaceAlt : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? AppTheme.accent : AppTheme.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        blurb,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 12,
      letterSpacing: 1,
      fontWeight: FontWeight.w700,
      color: AppTheme.textSecondary,
    ),
  );
}
