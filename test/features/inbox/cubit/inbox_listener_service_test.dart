import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_listener_service.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/services/share/peer_models.dart';
import 'package:noti_notes_app/services/share/share_codec.dart';

import '../../../repositories/received_inbox/fake_received_inbox_repository.dart';
import '../../../services/crypto/fake_keypair_service.dart';
import '../../../services/share/fake_peer_service.dart';

void main() {
  group('InboxListenerService', () {
    late Directory tempRoot;
    late FakePeerService peer;
    late FakeReceivedInboxRepository inbox;
    late FakeKeypairService keypair;
    late ShareDecoder decoder;
    late NotiIdentity identity;
    late InboxListenerService service;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('inbox_listener_test_');
      peer = FakePeerService();
      inbox = FakeReceivedInboxRepository();
      identity = NotiIdentity(
        id: 'me',
        displayName: 'Receiver',
        bornDate: DateTime.utc(2000, 1, 1),
        signaturePalette: const [
          Color(0xFF111111),
          Color(0xFF222222),
          Color(0xFF333333),
          Color(0xFF444444),
        ],
        signaturePatternKey: null,
        signatureAccent: null,
        signatureTagline: '',
        publicKey: List<int>.generate(32, (i) => i),
      );
      keypair = FakeKeypairService(publicKey: identity.publicKey);
      decoder = ShareDecoder(keypair: keypair, documentsRoot: tempRoot);
      service = InboxListenerService(
        peer: peer,
        decoder: decoder,
        inbox: inbox,
        identity: () => identity,
      );
    });

    tearDown(() async {
      await service.dispose();
      await peer.dispose();
      await inbox.dispose();
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('startReceiving starts peer in role=both and toggles isReceiving', () async {
      await service.startReceiving();
      expect(service.isReceiving, isTrue);
      expect(peer.actionLog, contains('start:both:Receiver'));
    });

    test('valid payload decodes into an inbox entry', () async {
      final firstReceived = service.events.firstWhere((e) => e is ShareReceived);
      await service.startReceiving();

      final senderIdentity = NotiIdentity(
        id: 'alex',
        displayName: 'Alex',
        bornDate: DateTime.utc(1995, 1, 1),
        signaturePalette: const [
          Color(0xFF112233),
          Color(0xFF445566),
          Color(0xFF778899),
          Color(0xFFAABBCC),
        ],
        signaturePatternKey: 'polygons',
        signatureAccent: '✦',
        signatureTagline: 'note from alex',
        publicKey: List<int>.generate(32, (i) => i + 100),
      );
      final senderKeypair = FakeKeypairService(publicKey: senderIdentity.publicKey);
      final note = _seedNote();

      final encoder = ShareEncoder(keypair: senderKeypair);
      final out = await encoder.encode(note: note, sender: senderIdentity);

      peer.payloads.add(IncomingPayload(peerId: 'p1', bytes: out.bytes));
      await firstReceived;

      final entries = await inbox.getAll();
      expect(entries, hasLength(1));
      expect(entries.first.sender.displayName, 'Alex');
    });

    test('tampered payload emits decodeRejected and inserts nothing', () async {
      final firstRejected = service.events.firstWhere((e) => e is DecodeRejected);
      await service.startReceiving();
      peer.payloads.add(const IncomingPayload(peerId: 'p1', bytes: <int>[1, 2, 3]));

      final event = await firstRejected;
      expect(event, isA<DecodeRejected>());
      expect(await inbox.getAll(), isEmpty);
    });

    test('stopReceiving cancels subscription + stops peer; idempotent', () async {
      await service.startReceiving();
      await service.stopReceiving();
      await service.stopReceiving();

      expect(service.isReceiving, isFalse);
      expect(peer.actionLog.where((a) => a == 'stop'), hasLength(1));
    });
  });
}

Note _seedNote() {
  return Note(
    {},
    null,
    null,
    <Map<String, dynamic>>[],
    null,
    null,
    id: 'note-uuid',
    title: 'Dinner ideas',
    content: '',
    dateCreated: DateTime.utc(2026, 5, 9, 11),
    colorBackground: const Color(0xFFEDE6D6),
    fontColor: const Color(0xFF1C1B1A),
    hasGradient: false,
    isPinned: false,
    blocks: const <Map<String, dynamic>>[
      {'type': 'text', 'id': 'b1', 'text': 'Hi'},
    ],
  );
}
