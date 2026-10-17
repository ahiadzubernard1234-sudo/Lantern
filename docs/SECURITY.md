# LANtern security model

## Encrypted, authenticated connections

Every TCP connection between two phones starts with a signed hello:

1. Each install has a long-term **Ed25519 identity key** (created on first launch).
2. Each connection generates a fresh **X25519 ephemeral key**, signed by the identity key.
3. Both sides verify the signature, derive two directional keys with HKDF-SHA256, and encrypt every frame with **ChaCha20-Poly1305**.
4. A message is dropped unless its `senderId` matches the device that authenticated the connection (no sender spoofing).

Fresh keys per connection give forward secrecy for past sessions.

## Peer authentication (trust on first use)

The first time a device is seen, its identity key is pinned in the `trusted_peers` table. If a known device later shows a **different** key, the connection is rejected and a `TrustAlert` is emitted (`NetworkServiceCoordinator.trustAlerts`).

Users can compare fingerprints out of band (`localFingerprint` / `peerFingerprint`) and call `CryptoService.markVerified(deviceId)`. `CryptoService.acceptKeyChange(deviceId)` accepts a rejected new key after the user decides to trust it.

## Offline delivery (outbox)

Messages are written to the `outbox` table when sent and removed on ACK. When a peer reappears on the network, queued messages are resent with a fresh timestamp (the original time is kept in `originalTimestamp` metadata). Messages older than 7 days or retried more than 20 times are dropped. Receivers re-ACK duplicates, so a lost ACK does not cause endless retries.

## Discovery

The UDP broadcast uses the subnet mask to compute the real broadcast address (falls back to /24), also sends to `255.255.255.255`, and trusts the packet's source address rather than the address it claims.

## Known limits

- Trust on first use cannot stop a man-in-the-middle on the very first contact. Verify fingerprints for sensitive chats.
- The identity key is stored in `shared_preferences`. Moving it to Android Keystore (`flutter_secure_storage`) is a recommended next step.
- UDP discovery packets are not authenticated; a fake peer entry only causes a failed handshake.
- Router/AP client isolation still blocks peer-to-peer traffic.
