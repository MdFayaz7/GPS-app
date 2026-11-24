import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/map_tiles.dart';
import '../theme.dart';
import '../widgets/info_card.dart';
import 'location_picker_screen.dart';

/// Stamp settings with a live preview of how the stamp will look.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _note = TextEditingController(text: widget.state.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Stamp settings')),
        body: ListenableBuilder(
          listenable: widget.state,
          builder: (context, child) => _body(widget.state),
        ),
      );

  Widget _body(AppState s) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const _Label('Preview'),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 260,
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.fromLTRB(13, 8, 13, 7),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF9CC7EE),
                    Color(0xFFCFE3F2),
                    Color(0xFF7DB45A),
                    Color(0xFF4C8A33),
                  ],
                  stops: [0, 0.38, 0.42, 1],
                ),
              ),
              child: IgnorePointer(child: InfoCard(state: s)),
            ),
          ),
          const SizedBox(height: 22),
          const _Label('Show on photo'),
          _Section(children: [
            _switch('Map', 'Mini map with location pin', Icons.map_outlined,
                s.showMap, (v) => s.updateStamp(showMap: v)),
            _switch('Address', 'Full street address', Icons.home_outlined,
                s.showAddress, (v) => s.updateStamp(showAddress: v)),
            _switch('Latitude / Longitude', 'GPS coordinates',
                Icons.explore_outlined, s.showCoords,
                (v) => s.updateStamp(showCoords: v)),
            _switch('Date & time', 'Day, date, time and time zone',
                Icons.schedule_rounded, s.showDate,
                (v) => s.updateStamp(showDate: v)),
          ]),
          const SizedBox(height: 22),
          const _Label('Map style'),
          _Section(children: [
            _choice(s.mapStyle == MapStyle.satellite, 'Satellite',
                'Aerial imagery', Icons.satellite_alt_outlined,
                () => s.updateStamp(mapStyle: MapStyle.satellite)),
            _choice(s.mapStyle == MapStyle.street, 'Street map',
                'Roads and place names', Icons.map_outlined,
                () => s.updateStamp(mapStyle: MapStyle.street)),
          ]),
          const SizedBox(height: 22),
          const _Label('Note'),
          TextField(
            controller: _note,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Site visit – Block A',
              prefixIcon: Icon(Icons.sticky_note_2_outlined,
                  color: AppColors.muted),
            ),
            onChanged: (v) => s.updateStamp(note: v.trim()),
          ),
          const SizedBox(height: 12),
          const _Label('Location'),
          _Section(children: [
            ListTile(
              leading: const _TileIcon(Icons.edit_location_alt_outlined),
              title: const Text('Custom location', style: _Section.title),
              subtitle: Text(
                s.custom?.title ?? 'Not set – pick a place on the map',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _Section.subtitle,
              ),
              trailing:
                  const Icon(Icons.chevron_right, color: AppColors.muted),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LocationPickerScreen(state: s))),
            ),
          ]),
          const SizedBox(height: 22),
          const _Label('Photo quality'),
          _Section(children: [
            _choice(s.highQuality, 'High · 4:3', 'Full resolution, best detail',
                Icons.hd_outlined, () => s.updateStamp(highQuality: true)),
            _choice(!s.highQuality, 'Standard · 16:9',
                '1080p, faster and smaller files', Icons.photo_camera_outlined,
                () => s.updateStamp(highQuality: false)),
          ]),
        ],
      );

  Widget _switch(String title, String sub, IconData icon, bool v,
          ValueChanged<bool> onChanged) =>
      SwitchListTile(
        secondary: _TileIcon(icon),
        title: Text(title, style: _Section.title),
        subtitle: Text(sub, style: _Section.subtitle),
        value: v,
        onChanged: onChanged,
      );

  Widget _choice(bool on, String title, String sub, IconData icon,
          VoidCallback onTap) =>
      ListTile(
        leading: _TileIcon(icon),
        title: Text(title, style: _Section.title),
        subtitle: Text(sub, style: _Section.subtitle),
        trailing: Icon(
            on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: on ? AppColors.primary : AppColors.border),
        onTap: onTap,
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.children});
  final List<Widget> children;

  static const title = TextStyle(
      color: AppColors.text, fontSize: 14.5, fontWeight: FontWeight.w600);
  static const subtitle = TextStyle(color: AppColors.muted, fontSize: 12);

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: 64),
              children[i],
            ],
          ]),
        ),
      );
}

class _TileIcon extends StatelessWidget {
  const _TileIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0x1A14BEF0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      );
}
