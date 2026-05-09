import 'package:noti_notes_app/services/share/peer_service.dart';

/// Wire-format version stamped into every encoded share manifest. A bump
/// here is a hard break: receivers on prior versions reject the payload
/// with [DecodeUnsupportedVersion] rather than guess at the new schema.
const int shareFormatVersion = 1;

/// Byte cap for an encoded share archive. Mirrors the transport ceiling so
/// the codec rejects oversize payloads before [PeerService.send] would.
const int shareMaxPayloadBytes = peerPayloadMaxBytes;

/// Archive entry names, kept in one place so encoder + decoder agree.
const String shareManifestEntry = 'manifest.json';
const String shareSignatureEntry = 'signature.bin';
const String shareImagesDir = 'assets/images';
const String shareAudioDir = 'assets/audio';
const String shareTranscriptsDir = 'assets/transcripts';
