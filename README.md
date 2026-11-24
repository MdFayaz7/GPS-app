# GPS Camera (Android, Flutter)

Takes photos with a geotag card burned in: mini map, address, lat/long, date and time, and an optional note. The location comes from **live GPS** or a **custom location** you pick on a map. The styling borrows from Practo: cyan actions, navy text, light grey background.

## Features
- Camera: back/front switch, flash off/auto/on, 1080p capture
- Live GPS with accuracy readout. Street address is looked up again only after you move about 25 m
- Custom location: drag the map pin, search a place, type coordinates, or reuse up to 6 recent places. Name and address can be edited
- The card in the preview is stamped onto the photo exactly as shown
- GPS coordinates and capture time are written into the photo's EXIF metadata
- Photos are saved to Gallery › **GPS Camera**, with preview and share
- Stamp settings (stored on the phone): mini map, coordinates, date/time and note

## Free services, no API keys
- Maps: OpenStreetMap tiles
- Addresses: the phone's built-in Android Geocoder

## Built to be light
- Compositing, JPEG encoding and EXIF writing run in Kotlin on a background thread ([MainActivity.kt](android/app/src/main/kotlin/com/sphurthy/gps_camera/MainActivity.kt)). Dart only renders the small card image
- The camera and GPS stop while the app is in the background or another screen is open
- Map tiles are cached in memory, and duplicate requests are merged
- Only the info card redraws, at most once a minute or when the location changes

## Run
```bash
./setup.sh        # flutter create (keeps existing files) + pub get
flutter run
flutter build apk --release --split-per-abi
```

## Structure
```
lib/
  main.dart                      app entry and theme
  theme.dart                     Practo-style colours and components
  app_state.dart                 GPS, custom location, settings (ChangeNotifier)
  services/map_tiles.dart        OSM tile math and cache
  services/photo_stamper.dart    card rendering, call to native stamping
  widgets/info_card.dart         geotag card
  widgets/mini_map.dart          map thumbnail
  screens/camera_screen.dart     camera, mode switch, settings sheet
  screens/location_picker_screen.dart
  screens/preview_screen.dart
```
