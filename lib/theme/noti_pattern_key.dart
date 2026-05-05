/// Closed list of bundled pattern PNGs under lib/assets/images/patterns/.
/// Each enum value's `name` is the persisted key on
/// `NotiIdentity.signaturePatternKey`; `assetBasename` matches the file on
/// disk (which preserves the existing `klaeidoscope` typo).
enum NotiPatternKey {
  waves('wavesRegulatedPNG'),
  wavesUnregulated('wavesUnregulatedPNG'),
  polygons('polygons'),
  kaleidoscope('klaeidoscope'),
  splashes('splashesPNG'),
  noise('pureNoisePNG'),
  upScaleWaves('upScaleWavesPNG');

  const NotiPatternKey(this.assetBasename);

  final String assetBasename;

  String get assetPath => 'lib/assets/images/patterns/$assetBasename.png';

  static NotiPatternKey? fromString(String? key) {
    if (key == null) return null;
    for (final p in NotiPatternKey.values) {
      if (p.name == key) return p;
    }
    return null;
  }
}
