import Foundation
import MediaPlayer
import UIKit
import ImageIO

@MainActor
extension NowPlayingService {
    public func setArtworkDecodeMaxPixelSize(_ size: CGFloat) {
        guard size > 0 else { return }
        artworkMasterMaxPixelSize = size
    }

    public func clearSuppressedMIMEs() {
        suppressedMIMEUntil.removeAll()
    }

    public func setArtwork(from urlString: String?) {
        if urlString == nil {
            clearArtwork()
            return
        }

        artworkTask?.cancel()
        artworkTask = nil

        guard let s = urlString, let url = URL(string: s) else { return }
        guard url.scheme?.lowercased() == "https" else { return }

        startPathMonitorIfNeeded()

        artworkGeneration += 1
        let token = artworkGeneration

        if info[MPMediaItemPropertyArtwork] == nil {
            let placeholder = buildPlaceholderArtwork(for: url, scale: UIScreen.main.scale)
            applyNowPlaying {
                $0[MPMediaItemPropertyArtwork] = placeholder
            }
        }

        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: artworkRequestTimeout)
        request.httpMethod = "GET"
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let originalHost = NowPlayingService.normalizeHostASCII(url.host ?? "")
        let redirectAllowlist = self.allowedRedirectHosts.map { Array($0) }
        let orgDomains = self.allowedRedirectOrgDomains.map { Array($0) }
        let screenScale = UIScreen.main.scale
        let isCompactLayout: Bool = {
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) {
                let tc = scene.traitCollection
                return tc.horizontalSizeClass == .compact || tc.verticalSizeClass == .compact
            }
            let tc = UIScreen.main.traitCollection
            return tc.horizontalSizeClass == .compact || tc.verticalSizeClass == .compact
        }()
        let decodeCap = self.artworkMasterMaxPixelSize
        let allowedMimes = self.allowedImageMIMETypes
        let maxBytes = self.artworkMaxBytes
        let runtimeSupportedMimes = self.runtimeSupportedMIMEs
        let decodeThreshold = self.decodeSuppressionThreshold
        let onCellular = self.isCellular
        let wifiTimeout = self.artworkRequestTimeout
        let timeoutOverrideHosts = self.cellularTimeoutOverrideHosts?.map { $0.lowercased() }

        artworkTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }

            var data = Data()
            var fetchSucceeded = false

            var currentMimeType: String? = nil

            func shortBackoff() async {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }

            attemptLoop: for attempt in 0..<2 {
                if Task.isCancelled { return }
                data.removeAll(keepingCapacity: false)

                do {
                    let appliedTimeout: TimeInterval
                    if onCellular {
                        let host = originalHost
                        let overrideFast = (host != nil) && (timeoutOverrideHosts?.contains(host!) ?? false)
                        if overrideFast {
                            appliedTimeout = wifiTimeout
                        } else {
                            if attempt == 0 {
                                let base = await MainActor.run { () -> TimeInterval in
                                    let h = host ?? ""
                                    let est = (!h.isEmpty) ? self.ewmaEstimate(for: h) : self.cellularFastTimeout
                                    return est
                                }
                                let clamped = min(max(base, self.minFirstAttemptCellularTimeout), self.maxFirstAttemptCellularTimeout)
                                appliedTimeout = clamped
                            } else {
                                appliedTimeout = wifiTimeout
                            }
                        }
                    } else {
                        appliedTimeout = wifiTimeout
                    }
                    var req = request
                    req.timeoutInterval = appliedTimeout

                    let session = self.urlSession
                    #if DEBUG
                    assert(session.configuration.urlCache != nil, "URLSession must have a URLCache for conditional GET validators.")
                    #endif

                    let fetchStart = ProcessInfo.processInfo.systemUptime
                    let (bytes, resp) = try await session.bytes(for: req, delegate: nil)
                    if Task.isCancelled { return }
                    guard let http = resp as? HTTPURLResponse else {
                        return
                    }
                    let validation = NowPlayingService.isFinalURLAllowed(finalURL: http.url, originalHostASCII: originalHost, redirectAllowlist: redirectAllowlist, orgDomains: orgDomains)
                    if !validation.allowed { return }
                    let finalHostASCII = validation.finalHostASCII

                    if http.statusCode == 304 {
                        if let cache = session.configuration.urlCache,
                           let cached = cache.cachedResponse(for: req),
                           let cachedHTTP = cached.response as? HTTPURLResponse {
                            if let ct = cachedHTTP.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                                let cachedMime = ct.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ct
                                currentMimeType = cachedMime
                                let allowedMimesRuntime = allowedMimes.intersection(runtimeSupportedMimes)
                                let isSuppressed = await MainActor.run { () -> Bool in
                                    if let until = self.suppressedMIMEUntil[cachedMime], until > Date() {
                                        return true
                                    } else if let until = self.suppressedMIMEUntil[cachedMime], until <= Date() {
                                        self.suppressedMIMEUntil.removeValue(forKey: cachedMime)
                                        self.enforceMimeSuppressionCap()
                                        return false
                                    }
                                    return false
                                }
                                guard allowedMimesRuntime.contains(cachedMime) else {
                                    return
                                }
                                if isSuppressed {
                                    return
                                }
                            }
                            else {
                                return
                            }
                            data = cached.data
                            let fetchDuration = ProcessInfo.processInfo.systemUptime - fetchStart

                            if let h = finalHostASCII ?? originalHost {
                                await MainActor.run { self.updateEWMA(for: h, sample: fetchDuration) }
                            }

                            fetchSucceeded = true
                        } else {
                            var fallbackReq = req
                            fallbackReq.cachePolicy = .reloadIgnoringLocalCacheData
                            fallbackReq.setValue(nil, forHTTPHeaderField: "If-None-Match")
                            fallbackReq.setValue(nil, forHTTPHeaderField: "If-Modified-Since")
                            fallbackReq.setValue("image/*", forHTTPHeaderField: "Accept")

                            let session2 = self.urlSession
                            #if DEBUG
                            assert(session2.configuration.urlCache != nil, "URLSession must have a URLCache for conditional GET validators.")
                            #endif

                            var finalHostASCIIForFallback: String? = nil

                            let (bytes2, resp2) = try await session2.bytes(for: fallbackReq, delegate: nil)

                            if let http2 = resp2 as? HTTPURLResponse {
                                let validation2 = NowPlayingService.isFinalURLAllowed(finalURL: http2.url, originalHostASCII: originalHost, redirectAllowlist: redirectAllowlist, orgDomains: orgDomains)
                                finalHostASCIIForFallback = validation2.finalHostASCII
                                #if DEBUG
                                if !validation2.allowed { assertionFailure("Redirect/HTTPS policy must be respected on 304 fallback") }
                                #endif
                                if !validation2.allowed { return }
                                if let contentTypeHeader2 = http2.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                                    let mimeType2 = contentTypeHeader2.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? contentTypeHeader2
                                    let allowedMimesRuntime2 = allowedMimes.intersection(runtimeSupportedMimes)
                                    let isSuppressed2 = await MainActor.run { () -> Bool in
                                        if let until = self.suppressedMIMEUntil[mimeType2], until > Date() {
                                            return true
                                        } else if let until = self.suppressedMIMEUntil[mimeType2], until <= Date() {
                                            self.suppressedMIMEUntil.removeValue(forKey: mimeType2)
                                            self.enforceMimeSuppressionCap()
                                            return false
                                        }
                                        return false
                                    }
                                    guard allowedMimesRuntime2.contains(mimeType2) else { return }
                                    if isSuppressed2 { return }
                                }
                                else {
                                    return
                                }
                                if let lenStr2 = http2.value(forHTTPHeaderField: "Content-Length"), let len2 = Int(lenStr2), len2 > maxBytes {
                                    return
                                }
                            }

                            data.removeAll(keepingCapacity: false)
                            for try await chunk in bytes2 {
                                if Task.isCancelled { return }
                                data.append(chunk)
                                if data.count > maxBytes {
                                    return
                                }
                            }
                            let fetchDuration2 = ProcessInfo.processInfo.systemUptime - fetchStart
                            if let h = finalHostASCIIForFallback ?? originalHost {
                                await MainActor.run { self.updateEWMA(for: h, sample: fetchDuration2) }
                            }
                            fetchSucceeded = true
                        }
                        break attemptLoop
                    }
                    guard (200...299).contains(http.statusCode) else {
                        if (500...599).contains(http.statusCode), attempt == 0 {
                            await shortBackoff()
                            continue attemptLoop
                        } else {
                            return
                        }
                    }
                    guard let contentTypeHeader = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() else {
                        return
                    }
                    let mimeType = contentTypeHeader.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? contentTypeHeader
                    currentMimeType = mimeType
                    let allowedMimesRuntime = allowedMimes.intersection(runtimeSupportedMimes)
                    let isSuppressed = await MainActor.run { () -> Bool in
                        if let until = self.suppressedMIMEUntil[mimeType], until > Date() {
                            return true
                        } else if let until = self.suppressedMIMEUntil[mimeType], until <= Date() {
                            self.suppressedMIMEUntil.removeValue(forKey: mimeType)
                            self.enforceMimeSuppressionCap()
                            return false
                        }
                        return false
                    }
                    guard allowedMimesRuntime.contains(mimeType) else {
                        return
                    }
                    if isSuppressed {
                        return
                    }
                    if let lenStr = http.value(forHTTPHeaderField: "Content-Length"), let len = Int(lenStr), len > maxBytes {
                        return
                    }
                    for try await chunk in bytes {
                        if Task.isCancelled { return }
                        data.append(chunk)
                        if data.count > maxBytes {
                            return
                        }
                    }

                    let fetchDuration = ProcessInfo.processInfo.systemUptime - fetchStart
                    if let h = finalHostASCII ?? originalHost {
                        await MainActor.run { self.updateEWMA(for: h, sample: fetchDuration) }
                    }

                    fetchSucceeded = true
                    break attemptLoop
                } catch {
                    if Task.isCancelled { return }
                    if attempt == 0 {
                        await shortBackoff()
                        continue attemptLoop
                    } else {
                        return
                    }
                }
            }

            guard fetchSucceeded else { return }
            if Task.isCancelled { return }

            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
                if let m = currentMimeType {
                    await MainActor.run {
                        let next = (self.mimeDecodeFailureCounts[m] ?? 0) + 1
                        self.mimeDecodeFailureCounts[m] = next
                        if next >= decodeThreshold {
                            self.suppressedMIMEUntil[m] = Date().addingTimeInterval(self.mimeSuppressionTTL)
                            self.enforceMimeSuppressionCap()
                        }
                    }
                }
                return
            }

            let masterOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: decodeCap * screenScale
            ]
            guard let masterCG = CGImageSourceCreateThumbnailAtIndex(src, 0, masterOpts as CFDictionary) else {
                if let m = currentMimeType {
                    await MainActor.run {
                        let next = (self.mimeDecodeFailureCounts[m] ?? 0) + 1
                        self.mimeDecodeFailureCounts[m] = next
                        if next >= decodeThreshold {
                            self.suppressedMIMEUntil[m] = Date().addingTimeInterval(self.mimeSuppressionTTL)
                            self.enforceMimeSuppressionCap()
                        }
                    }
                }
                return
            }

            data.removeAll(keepingCapacity: false)

            let boundsSize = CGSize(width: CGFloat(masterCG.width) / screenScale, height: CGFloat(masterCG.height) / screenScale)

            func cgImageScaled(_ image: CGImage, toPixelSize size: CGSize) -> CGImage? {
                guard size.width > 0, size.height > 0 else { return nil }
                let targetW = max(1, Int(round(size.width)))
                let targetH = max(1, Int(round(size.height)))
                if targetW == image.width && targetH == image.height { return nil }
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bytesPerPixel = 4
                let bitsPerComponent = 8
                let bytesPerRow = targetW * bytesPerPixel
                guard let ctx = CGContext(data: nil,
                                          width: targetW,
                                          height: targetH,
                                          bitsPerComponent: bitsPerComponent,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                ctx.interpolationQuality = .high
                ctx.draw(image, in: CGRect(origin: .zero, size: CGSize(width: targetW, height: targetH)))
                return ctx.makeImage()
            }

            let strategy = await MainActor.run { self.bucketStrategy }
            let masterMaxPixels = CGFloat(max(masterCG.width, masterCG.height))
            let masterMaxPoints = masterMaxPixels / screenScale
            var cgBucketImages: [Int: CGImage] = [:]

            let effectiveStrategy: ArtworkBucketStrategy = (masterMaxPoints < 480) ? .one : strategy

            var bucketPoints: [Int]
            switch effectiveStrategy {
            case .one:  bucketPoints = [NowPlayingService.bucketThresholds[1]]
            case .two:  bucketPoints = [NowPlayingService.bucketThresholds[0], NowPlayingService.bucketThresholds[1]]
            case .three: bucketPoints = NowPlayingService.bucketThresholds
            }

            let allow1024 = (masterMaxPoints >= 900) && (!isCompactLayout)
            if !allow1024 {
                bucketPoints.removeAll { $0 == NowPlayingService.bucketThresholds.last }
            }

            if let smallest = bucketPoints.min(), masterMaxPoints < CGFloat(smallest) {
            } else {
                for bp in bucketPoints {
                    let bpPoints = CGFloat(bp)
                    if bpPoints > masterMaxPoints { continue }
                    let scale = min(bpPoints / max(boundsSize.width, boundsSize.height), 1.0)
                    let targetPixels = CGSize(width: boundsSize.width * scale * screenScale,
                                              height: boundsSize.height * scale * screenScale)
                    if let scaled = cgImageScaled(masterCG, toPixelSize: targetPixels) {
                        cgBucketImages[bp] = scaled
                    }
                }
            }

            await MainActor.run {
                guard token == self.artworkGeneration else { return }
                if Task.isCancelled { return }

                let control = ArtworkCacheControl()

                let masterImage = UIImage(cgImage: masterCG, scale: screenScale, orientation: .up)

                var builtBuckets: [Int: UIImage] = [:]
                for (k, v) in cgBucketImages {
                    builtBuckets[k] = UIImage(cgImage: v, scale: screenScale, orientation: .up)
                }
                let now = Date()
                let shouldDefer = ((self.bucketRehydrateUntil != nil && now < self.bucketRehydrateUntil!) || self.isBackgrounded || ((self.lastPublishedRate ?? 0) == 0))
                if shouldDefer {
                    control.buckets = nil
                } else {
                    control.buckets = builtBuckets
                }
                control.master = masterImage
                control.placeholder = self.lastPlaceholderImage

                if let prev = self.currentArtworkControl {
                    let s = prev.metrics.snapshot()
                    let total = s.le256 + s.le512 + s.gt512
                    if total >= 20 {
                        let small = s.le256 + s.le512
                        let ratio = Double(small) / Double(max(1, total))
                        var proposed: ArtworkBucketStrategy? = nil
                        if ratio >= 0.9 {
                            proposed = (s.gt512 == 0 && s.le512 > 0 && s.le256 == 0) ? .one : .two
                        }
                        if let proposed {
                            let current = self.bucketStrategy
                            let now = Date()
                            let currentCount = self.bucketCount(current)
                            let proposedCount = self.bucketCount(proposed)
                            if proposedCount > currentCount {
                                if let until = self.bucketStrategyCooldownUntil, until > now {
                                } else {
                                    self.bucketStrategy = proposed
                                }
                            } else if proposedCount < currentCount {
                                self.bucketStrategy = proposed
                                self.bucketStrategyCooldownUntil = now.addingTimeInterval(self.bucketStrategyCooldown)
                            }
                        }
                    }
                }

                #if DEBUG
                precondition((control.buckets?.count ?? 0) <= 3, "Artwork cache should be bounded to <= 3 buckets")
                #endif

                let providerFallbackImage = control.placeholder ?? control.master ?? self.tinyFallbackImage

                let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { requested in
                    #if DEBUG
                    precondition((control.buckets?.count ?? 0) <= 3, "Artwork cache should be bounded to <= 3 buckets")
                    #endif

                    let maxDim = max(requested.width, requested.height)
                    control.metrics.record(requestedMaxDimension: maxDim)

                    return control.imageFor(requested: requested, boundsSize: boundsSize) ?? providerFallbackImage
                }

                self.currentArtworkControl = control

                self.applyNowPlaying {
                    $0[MPMediaItemPropertyArtwork] = artwork
                }
            }
        }
    }

    public func clearArtwork() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkGeneration += 1

        applyNowPlaying {
            $0.removeValue(forKey: MPMediaItemPropertyArtwork)
        }

        currentArtworkControl = nil

        schedulePathMonitorStop()
    }
}
