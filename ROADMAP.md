# Roadmap

This is a portfolio project, so the roadmap doubles as an honest list of what is
**not** production-ready yet and how I would close each gap. Items are grouped by
theme, roughly in priority order. Nothing here is a promise or a date.

Legend: `[x]` done · `[ ]` planned · `[?]` under consideration

---

## v0.1: Done

### Media and connectivity
- [x] Peer-to-peer audio and H.264 video over WebRTC between iOS, iPadOS and macOS
- [x] One Camera, several Viewers: a separate peer connection per Viewer
- [x] Pairing with a QR code deep link (`<bundle id>://join?roomID=...`) or a typed Room ID
- [x] Camera switching between available capture devices
- [x] Capture resolution and frame rate chosen from the negotiated H.264 level, so weaker receivers do not break the encoder
- [x] Camera rejoin: when the Camera comes back to the room, the Viewer sends a new offer and the Camera answers with a working video track

### Signaling and concurrency
- [x] Offer collision (glare) handling: the Viewer is the polite peer, the Camera the impolite one
- [x] ICE candidate buffering until the remote description is set, applied in order afterwards
- [x] Stale-connection protection: callbacks and sends from replaced WebSocket connections are ignored
- [x] Explicit threading: one serial session queue owns session state; view models run on `MainActor`
- [x] Camera and microphone permission flow before any capture or signaling starts

### Tooling and quality
- [x] Custom WebRTC M156 build with Intel Mac support ([why](README.md#why-a-custom-webrtc-build))
- [x] Unit tests (Swift Testing): ICE buffering, session lifecycle, signaling connections, SDP delivery through an in-process WebSocket server, capture permissions, QR scanning, logger
- [x] In-app debug log overlay in Debug builds
- [x] Sample Vapor signaling server as a Docker image

---

## v0.2+: Reliability

The current build works on a clean network and is fragile outside it.

- [ ] **Real "connected" state.** Report the socket as open only after the WebSocket handshake completes (`URLSessionWebSocketDelegate`), not right after `resume()`
- [ ] **ICE restart** after `disconnected` / `failed` instead of ending in a dead state
- [?] **Network changes.** Observe `NWPathMonitor` (Wi-Fi ↔ cellular) and recover
- [?] **Keep the Camera role alive.** Disable the idle timer while streaming.
- [?] Persist recent rooms (`UserDefaults`)
- [?] Surface connection errors to the user instead of only to the log
- [?] **Room access control.** Short-lived room tokens instead of a bare room ID;
- [?] Include the server address in the QR payload so the Viewer needs no manual setup

---

## Known limitations (until the items above land)

- STUN only, no TURN: strict NATs and some mobile networks will not connect
- No signaling reconnect; the session must be restarted after a network drop
- Room ID is the only access control; signaling is plaintext unless you add TLS

## Non-goals

- A general-purpose WebRTC library or SDK
- Group calls or an SFU (this is one camera → a few viewers, peer-to-peer)
- Recording, cloud storage, or accounts

## How to influence this roadmap

This repository is not maintained as a community project, so pull requests may not
be reviewed. If you need one of these items for your own product (TURN setup,
reconnect logic, a Swift signaling backend, a WebRTC audit), see the
[license section](README.md#license) and contact me.
