import 'package:noti_notes_app/services/share/peer_models.dart';

/// Two discovered peers in mixed connection states for the share-sheet
/// discover golden.
List<DiscoveredPeer> fixturePeers() => const [
      DiscoveredPeer(
        id: 'peer-1',
        displayName: 'Alex',
        state: PeerConnectionState.found,
      ),
      DiscoveredPeer(
        id: 'peer-2',
        displayName: 'Jamie',
        state: PeerConnectionState.found,
      ),
    ];
