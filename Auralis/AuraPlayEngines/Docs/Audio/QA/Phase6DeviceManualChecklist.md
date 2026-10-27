# Phase 6 Device / Manual QA Checklist

This checklist covers behavior CI cannot honestly prove. Run on a physical device before marking Phase 6 complete.

Reviewer: ____________________
Device / OS: ____________________
Date: ____________________

- [ ] Host app has wired `AuraPlayAudioEngine` into real playback flows with app queue state, user controls, route selection, cache persistence, and app-owned media adapters.
- [ ] Host app Info.plist sets `AVInitialRouteSharingPolicy` to `LongFormAudio` through Xcode's **AirPlay optimization policy** setting.
- [ ] Background audio continues when the app is backgrounded and the screen locks.
- [ ] Connect AirPods mid-playback: audio continues after configuration-change recovery.
- [ ] Disconnect AirPods mid-playback: audio pauses and does not switch loudly to speaker.
- [ ] Incoming phone call: audio pauses; after the call, audio resumes from the same position when `shouldResume` is true.
- [ ] Siri invocation mid-playback: interruption is handled and playback resumes correctly.
- [ ] Lock Screen shows correct title, artist, artwork, and advancing elapsed time.
- [ ] Lock Screen play, pause, skip, and scrub commands work.
- [ ] AirPods stem controls trigger the correct remote command events.
- [ ] AirPods automatic switching behaves correctly between iPhone and Mac when AuraPlay is actively publishing Now Playing for real long-form playback.
- [ ] Pausing playback stops audio without playing silence or keeping a fake silent route alive.
- [ ] The host app does not publish Now Playing for previews, notification sounds, app chimes, placeholders, onboarding sounds, or silent keepalives.
- [ ] The host app respects the user's selected route and does not automatically migrate between custom engine and AirPlay-optimized routes mid-track.
- [ ] App-specific chimes, if present, use a notification/chime path outside AuraPlay and do not appear as Now Playing media.
- [ ] AirPlay picker appears in the host playback UI and exposes HomePod/AirPlay targets when available.
- [ ] With `AVInitialRouteSharingPolicy` set to `LongFormAudio`, the app is eligible for long-form AirPlay suggestions after repeated use.
- [ ] AirPlay-optimized route plays through a HomePod or AirPlay speaker using `AirPlayQueuePlayerController`.
- [ ] HomePod or AirPlay speaker play/pause/skip controls trigger the correct remote command events.
- [ ] AirPlay playback survives a brief Wi-Fi range dropout and reconnect without an audible restart when using the AirPlay-optimized route.
- [ ] Wireless CarPlay playback uses the AirPlay-optimized route and responds to vehicle controls when a test vehicle/head unit is available.
- [ ] Spatial Audio availability is evaluated on AirPods using the AirPlay-optimized `AVQueuePlayer` route before any custom spatial graph work is proposed.
- [ ] `AuraSpatialAudioPolicy` is verified on device for `.none`, `.monoAndStereo`, `.multichannel`, and `.monoStereoAndMultichannel` with suitable source media.
- [ ] Host UI reflects spatial capability changes from route changes and Control Center/Bluetooth Spatial Audio settings without forcing the setting on.
- [ ] `AudioSessionManager.setSupportsMultichannelContent(_:)` is called when the host can offer multichannel content.
- [ ] Stereo and multichannel renditions are loudness-normalized; DRC and dialnorm metadata are verified in the content pipeline for HLS multichannel assets.
- [ ] If real ASAF/APAC assets exist, APAC spatial playback is evaluated through the system `AVQueuePlayer` route on supported hardware.
- [ ] If real ASAF/APAC assets include a stereo compatibility track, fallback playback is verified when APAC spatial playback is unavailable or disabled.
- [ ] If real ASAF/APAC assets are streamed, HLS/fMP4 APAC delivery is verified through system playback before any package-specific streaming code is proposed.
- [ ] Press to Mute is not exposed by AuraPlay playback UI; any future microphone feature owns its own mute state and QA.
- [ ] Voice processing, other-audio ducking, and muted talker detection are not exposed by AuraPlay playback UI or package APIs.
- [ ] If a future microphone/call/live-room feature exists, it owns AVAudioEngine voice processing or AUVoiceProcessingIO adoption, mute APIs, ducking policy, muted talker detection, and privacy QA outside this playback package.
- [ ] Poor-network progressive download starts playback within about 2 seconds and buffers gracefully on the custom engine route.
- [ ] A known gapless album transitions with no audible gap on device on the custom engine route.
- [ ] One-hour background audio battery drain is within the under-3% target on a recent device.

## Not Covered By Automated Tests

- Real route changes.
- Real interruptions from Phone and Siri.
- Background execution on the real system.
- Lock Screen and Control Center Now Playing behavior.
- AirPods automatic switching between Apple devices.
- Detection of accidental silent keepalive playback after pause.
- Verification that previews, chimes, and notifications do not register as Now Playing media.
- Remote command delivery from physical accessories.
- Real AirPlay/HomePod buffering, reconnect behavior, and route picker availability.
- Wireless CarPlay control behavior.
- `AVAudioPlayerNode` completion callback timing under real hardware playback.
