/// Maps a curated-palette display name (e.g. "Bone + Slate") to a filesystem
/// slug (e.g. "bone_slate") for golden filenames.
String paletteSlug(String displayName) {
  return displayName
      .toLowerCase()
      .replaceAll('+', ' ')
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .join('_');
}
