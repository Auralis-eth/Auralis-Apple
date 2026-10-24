import AudioToolbox
import AVFoundation
import Foundation

public final class AudioEngineController: AudioEngineControlling, AudioEffectsControlling, AudioVisualizationPublishing, @unchecked Sendable {
    public static let queueLabel = "com.auraplay.audio-engine"
    public static let scheduledChunkFrameCount: AVAudioFrameCount = 32_768
    public static let maxReadAheadBufferCount = 8

    internal let engine: AVAudioEngine
    internal let primaryPlayerNode: AVAudioPlayerNode
    internal let preBufferPlayerNode: AVAudioPlayerNode
    internal let trackMixerNode: AVAudioMixerNode
    internal let eqNode: AVAudioUnitEQ
    internal let dynamicsNode: AVAudioUnitEffect
    internal let processingFormat: AVAudioFormat
    public var renderSampleRate: Double {
        processingFormat.sampleRate
    }

    private let queue = DispatchQueue(label: AudioEngineController.queueLabel)
    private var graphIsBuilt = false
    private var activePlayerRole: PlayerRole = .primary
    private var spokenWordDynamicsEnabled = false
    private var normalizationGainDB: Float = 0
    private var lastScheduledFileURL: URL?
    private var lastScheduledFrame: AVAudioFramePositionValue = 0
    private var lastScheduledSourceSampleRate: Double = 48_000
    private var playNextWhenActiveStreamEnds = false
    private var automaticTransitionCount = 0
    private var activeStream: ScheduledAudioStream?
    private var inactiveStream: ScheduledAudioStream?
    private var plannedGaplessBoundaryFrame: AVAudioFramePositionValue?
    private var inactivePlayerStartedForPlannedTransition = false
    private var visualizationContinuation: AsyncStream<AudioVisualizationFrame>.Continuation?
    private var visualizationTapIsInstalled = false
    private var visualizationGeneration = 0

    public var graphDescription: EngineGraphDescription {
        syncOnQueue {
            EngineGraphDescription(
                customNodeNames: graphIsBuilt ? [
                    "primaryPlayerNode",
                    "preBufferPlayerNode",
                    "trackMixerNode",
                    "eqNode",
                    "dynamicsNode",
                ] : [],
                sampleRate: processingFormat.sampleRate,
                channelCount: Int(processingFormat.channelCount),
                connectionCount: liveConnectionCount(),
                containsEnvironmentNode: false
            )
        }
    }

    public func startVisualization(configuration: AudioVisualizationConfiguration = AudioVisualizationConfiguration()) -> AsyncStream<AudioVisualizationFrame> {
        syncOnQueue {
            buildGraphIfNeeded()
            removeVisualizationTap()

            visualizationGeneration += 1
            let generation = visualizationGeneration
            let streamPair = AsyncStream<AudioVisualizationFrame>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let continuation = streamPair.continuation
            visualizationContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard self?.visualizationGeneration == generation else {
                        return
                    }
                    self?.removeVisualizationTap()
                }
            }

            trackMixerNode.installTap(
                onBus: 0,
                bufferSize: configuration.bufferFrameCount(sampleRate: processingFormat.sampleRate),
                format: processingFormat
            ) { buffer, time in
                continuation.yield(AudioVisualizationAnalyzer.makeFrame(buffer: buffer, time: time))
            }
            visualizationTapIsInstalled = true
            return streamPair.stream
        }
    }

    public func stopVisualization() async {
        await asyncOnQueueWithoutResult {
            self.removeVisualizationTap()
        }
    }

    public init(
        engine: AVAudioEngine = AVAudioEngine(),
        sampleRate: Double = 48_000,
        channelCount: AVAudioChannelCount = 2
    ) throws {
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw AuraPlayError.engineStartFailed
        }

        self.engine = engine
        self.primaryPlayerNode = AVAudioPlayerNode()
        self.preBufferPlayerNode = AVAudioPlayerNode()
        self.trackMixerNode = AVAudioMixerNode()
        self.eqNode = AVAudioUnitEQ(numberOfBands: EQPreset.bandCenters.count)
        self.dynamicsNode = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        self.processingFormat = processingFormat

        syncOnQueue {
            self.buildGraphIfNeeded()
            self.configureEQBands(EQPreset.flat.gains)
            self.configureDynamicsDefaults()
        }
    }

    public func start() async throws {
        try await asyncOnQueue {
            self.buildGraphIfNeeded()
            self.engine.prepare()
            if !self.engine.isRunning {
                try self.engine.start()
            }
        }
    }

    public func stop() async {
        await asyncOnQueueWithoutResult {
            self.primaryPlayerNode.stop()
            self.preBufferPlayerNode.stop()
            self.engine.stop()
        }
    }

    public func pause() async {
        await asyncOnQueueWithoutResult {
            self.primaryPlayerNode.pause()
            self.preBufferPlayerNode.pause()
            self.engine.pause()
        }
    }

    public func resume() async throws {
        try await start()
        await asyncOnQueueWithoutResult {
            self.activePlayer.play()
            if self.inactivePlayerStartedForPlannedTransition || self.inactivePlayer.volume > 0 {
                self.inactivePlayer.play()
            }
        }
    }

    public func applyEQPreset(_ preset: EQPreset) async {
        await asyncOnQueueWithoutResult {
            self.configureEQBands(preset.gains)
        }
    }

    public func configureForContentKind(_ contentKind: AuraPlayableContentKind) async {
        await asyncOnQueueWithoutResult {
            self.spokenWordDynamicsEnabled = contentKind == .spokenWord
            self.applyDynamicsParameters()
        }
    }

    public func applyNormalizationGain(approxLoudnessLUFS: Double?) async {
        let gain = Float(LoudnessNormalization.gainDB(for: approxLoudnessLUFS))
        await asyncOnQueueWithoutResult {
            self.normalizationGainDB = gain
            self.applyDynamicsParameters()
        }
    }

    public func scheduleCurrent(fileURL: URL, startingFrame: AVAudioFramePositionValue = 0) async throws {
        try await asyncOnQueue {
            try self.schedule(fileURL: fileURL, on: self.activePlayer, startingFrame: startingFrame)
            self.lastScheduledFileURL = fileURL
            self.lastScheduledFrame = startingFrame
            if self.engine.isRunning {
                self.activePlayer.play()
            }
        }
    }

    public func scheduleNext(fileURL: URL) async throws {
        try await asyncOnQueue {
            try self.schedule(fileURL: fileURL, on: self.inactivePlayer, startingFrame: 0)
        }
    }

    public func playPreparedNext() async {
        await asyncOnQueueWithoutResult {
            self.performPreparedNextTransition()
        }
    }

    public func startInactivePlaybackForOverlap() async {
        await asyncOnQueueWithoutResult {
            self.inactivePlayer.play()
        }
    }

    public func armPreparedNextForGaplessTransition() async {
        await asyncOnQueueWithoutResult {
            self.playNextWhenActiveStreamEnds = true
            self.plannedGaplessBoundaryFrame = self.currentActiveGaplessBoundaryRenderFrame()
            self.inactivePlayerStartedForPlannedTransition = false

            if self.engine.isRunning, let boundaryFrame = self.plannedGaplessBoundaryFrame {
                let boundaryTime = AVAudioTime(
                    sampleTime: AVAudioFramePosition(boundaryFrame),
                    atRate: self.processingFormat.sampleRate
                )
                self.inactivePlayer.play(at: boundaryTime)
                self.inactivePlayerStartedForPlannedTransition = true
            }
        }
    }

    public func debugIsGaplessTransitionArmed() -> Bool {
        syncOnQueue {
            playNextWhenActiveStreamEnds
        }
    }

    public func debugAutomaticTransitionCount() -> Int {
        syncOnQueue {
            automaticTransitionCount
        }
    }

    public func debugPlannedGaplessBoundaryFrame() -> AVAudioFramePositionValue? {
        syncOnQueue {
            plannedGaplessBoundaryFrame
        }
    }

    public func debugMaxObservedReadAheadBufferCount() -> Int {
        syncOnQueue {
            max(activeStream?.maxObservedScheduledBufferCount ?? 0, inactiveStream?.maxObservedScheduledBufferCount ?? 0)
        }
    }

    public func debugPlayerVolumes() -> (active: Float, inactive: Float) {
        syncOnQueue {
            (activePlayer.volume, inactivePlayer.volume)
        }
    }

    public func setActiveVolume(_ volume: Float) async {
        await asyncOnQueueWithoutResult {
            self.activePlayer.volume = volume
        }
    }

    public func setInactiveVolume(_ volume: Float) async {
        await asyncOnQueueWithoutResult {
            self.inactivePlayer.volume = volume
        }
    }

    public func stopInactiveWhenSilent() async {
        await asyncOnQueueWithoutResult {
            if self.inactivePlayer.volume == 0 {
                self.inactivePlayer.stop()
            }
        }
    }

    public func currentFrame() async -> AVAudioFramePositionValue {
        await asyncOnQueue {
            guard
                let renderTime = self.activePlayer.lastRenderTime,
                let playerTime = self.activePlayer.playerTime(forNodeTime: renderTime)
            else {
                return self.lastScheduledFrame
            }
            let sourceFrameOffset = self.renderedFramesToSourceFrames(
                AVAudioFramePositionValue(playerTime.sampleTime),
                sourceSampleRate: self.lastScheduledSourceSampleRate
            )
            return self.lastScheduledFrame + sourceFrameOffset
        }
    }

    public func currentRenderFrame() async -> AVAudioFramePositionValue {
        await asyncOnQueue {
            self.currentActiveRenderFrame()
        }
    }

    public func restartPreservingGraph() async throws {
        try await asyncOnQueue {
            self.engine.stop()
            self.verifyGraphConnections()
            self.engine.prepare()
            try self.engine.start()
        }
    }

    public func rescheduleCurrentFromLastFile(startingFrame: AVAudioFramePositionValue) async throws {
        try await asyncOnQueue {
            guard let lastScheduledFileURL = self.lastScheduledFileURL else {
                return
            }
            try self.schedule(fileURL: lastScheduledFileURL, on: self.activePlayer, startingFrame: startingFrame)
            self.lastScheduledFrame = startingFrame
            if self.engine.isRunning {
                self.activePlayer.play()
            }
        }
    }

    public func scheduleNextAtHostBoundary(fileURL: URL) async throws -> AVAudioFramePositionValue {
        try await asyncOnQueue {
            try self.schedule(fileURL: fileURL, on: self.inactivePlayer, startingFrame: 0)
            let boundaryFrame = self.currentActiveFileRemainingRenderFrameCount()
            return boundaryFrame
        }
    }

    public func debugDynamicsParameterValue(_ address: AudioUnitParameterID) -> Float? {
        syncOnQueue {
            dynamicsNode.auAudioUnit.parameterTree?.parameter(withAddress: AUParameterAddress(address))?.value
        }
    }

    private var activePlayer: AVAudioPlayerNode {
        activePlayerRole == .primary ? primaryPlayerNode : preBufferPlayerNode
    }

    private var inactivePlayer: AVAudioPlayerNode {
        activePlayerRole == .primary ? preBufferPlayerNode : primaryPlayerNode
    }

    private func buildGraphIfNeeded() {
        guard !graphIsBuilt else {
            return
        }

        [primaryPlayerNode, preBufferPlayerNode, trackMixerNode, eqNode, dynamicsNode].forEach(engine.attach)
        verifyGraphConnections()
        graphIsBuilt = true
    }

    private func verifyGraphConnections() {
        engine.connect(primaryPlayerNode, to: trackMixerNode, format: processingFormat)
        engine.connect(preBufferPlayerNode, to: trackMixerNode, format: processingFormat)
        engine.connect(trackMixerNode, to: eqNode, format: processingFormat)
        engine.connect(eqNode, to: dynamicsNode, format: processingFormat)
        engine.connect(dynamicsNode, to: engine.mainMixerNode, format: processingFormat)
    }

    private func liveConnectionCount() -> Int {
        [primaryPlayerNode, preBufferPlayerNode, trackMixerNode, eqNode, dynamicsNode]
            .reduce(0) { count, node in
                count + engine.outputConnectionPoints(for: node, outputBus: 0).count
            }
    }

    private func removeVisualizationTap() {
        visualizationGeneration += 1
        guard visualizationTapIsInstalled else {
            visualizationContinuation?.finish()
            visualizationContinuation = nil
            return
        }

        trackMixerNode.removeTap(onBus: 0)
        visualizationTapIsInstalled = false
        visualizationContinuation?.finish()
        visualizationContinuation = nil
    }

    private func configureEQBands(_ gains: [Float]) {
        for (index, band) in eqNode.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = EQPreset.bandCenters[index]
            band.bandwidth = 1.0
            band.gain = gains[index]
            band.bypass = false
        }
    }

    private func configureDynamicsDefaults() {
        spokenWordDynamicsEnabled = false
        normalizationGainDB = 0
        applyDynamicsParameters()
    }

    private func applyDynamicsParameters() {
        dynamicsNode.bypass = !spokenWordDynamicsEnabled && normalizationGainDB == 0
        setDynamicsParameter(kDynamicsProcessorParam_Threshold, value: -18)
        setDynamicsParameter(kDynamicsProcessorParam_HeadRoom, value: 5)
        setDynamicsParameter(kDynamicsProcessorParam_AttackTime, value: 0.003)
        setDynamicsParameter(kDynamicsProcessorParam_ReleaseTime, value: 0.05)
        setDynamicsParameter(kDynamicsProcessorParam_OverallGain, value: normalizationGainDB)
    }

    private func setDynamicsParameter(_ parameterID: AudioUnitParameterID, value: Float) {
        let address = AUParameterAddress(parameterID)
        dynamicsNode.auAudioUnit.parameterTree?.parameter(withAddress: address)?.value = value
    }

    private func performPreparedNextTransition() {
        if !inactivePlayerStartedForPlannedTransition {
            inactivePlayer.play()
        }
        swap(&activeStream, &inactiveStream)
        activePlayerRole = activePlayerRole == .primary ? .preBuffer : .primary
        lastScheduledFrame = 0
        lastScheduledSourceSampleRate = activeStream?.sourceSampleRate ?? processingFormat.sampleRate
        playNextWhenActiveStreamEnds = false
        plannedGaplessBoundaryFrame = nil
        inactivePlayerStartedForPlannedTransition = false
        automaticTransitionCount += 1
    }

    private func schedule(
        fileURL: URL,
        on player: AVAudioPlayerNode,
        startingFrame: AVAudioFramePositionValue
    ) throws {
        guard fileURL.isFileURL else {
            throw AuraPlayError.invalidMediaURL(fileURL)
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: fileURL)
        } catch {
            throw AuraPlayError.corruptedFile(fileURL)
        }

        let startFrame = max(0, min(startingFrame, file.length))
        player.stop()
        player.volume = 1
        file.framePosition = startFrame
        if player === activePlayer {
            plannedGaplessBoundaryFrame = nil
            inactivePlayerStartedForPlannedTransition = false
            playNextWhenActiveStreamEnds = false
        }

        let stream = ScheduledAudioStream(
            file: file,
            player: player,
            processingFormat: processingFormat,
            sourceFrameLength: file.length,
            sourceSampleRate: file.fileFormat.sampleRate,
            maxReadAheadBufferCount: Self.maxReadAheadBufferCount,
            enqueueOnEngineQueue: { [weak self] operation in
                self?.queue.async(execute: operation)
            },
            convertBuffer: { [weak self] file, frameCount in
                guard let self else {
                    throw AuraPlayError.engineStartFailed
                }
                return try self.convertedBuffer(from: file, frameCount: frameCount)
            },
            onFinalBufferConsumed: { [weak self] in
                guard let self, self.playNextWhenActiveStreamEnds else {
                    return
                }
                self.performPreparedNextTransition()
            }
        )

        if player === activePlayer {
            activeStream = stream
            lastScheduledSourceSampleRate = file.fileFormat.sampleRate
        } else {
            inactiveStream = stream
        }

        guard file.length > startFrame else {
            return
        }

        try stream.scheduleMoreBuffers()
    }

    private func convertedBuffer(from file: AVAudioFile, frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            throw AuraPlayError.corruptedFile(file.url)
        }
        try file.read(into: inputBuffer, frameCount: frameCount)
        guard inputBuffer.frameLength > 0 else {
            return nil
        }

        if file.processingFormat == processingFormat {
            return inputBuffer
        }

        guard
            let converter = AVAudioConverter(from: file.processingFormat, to: processingFormat),
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: convertedFrameCapacity(inputFrames: inputBuffer.frameLength, from: file.processingFormat)
            )
        else {
            throw AuraPlayError.corruptedFile(file.url)
        }

        var didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            status.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw AuraPlayError.downloadFailed(conversionError.localizedDescription)
        }
        return outputBuffer
    }

    private func convertedFrameCapacity(inputFrames: AVAudioFrameCount, from inputFormat: AVAudioFormat) -> AVAudioFrameCount {
        let ratio = processingFormat.sampleRate / inputFormat.sampleRate
        return AVAudioFrameCount(ceil(Double(inputFrames) * ratio)) + 16
    }

    private func currentActiveFileRemainingRenderFrameCount() -> AVAudioFramePositionValue {
        guard let activeStream else {
            return 0
        }
        let currentSourceFrame = currentActiveSourceFrame()
        let remainingSourceFrames = max(0, activeStream.sourceFrameLength - currentSourceFrame)
        return sourceFramesToRenderFrames(remainingSourceFrames, sourceSampleRate: activeStream.sourceSampleRate)
    }

    private func currentActiveGaplessBoundaryRenderFrame() -> AVAudioFramePositionValue? {
        guard activeStream != nil else {
            return nil
        }
        // play(at:) interprets the boundary on the node (engine render) timeline, not the
        // player's playback-relative timeline, so anchor it to lastRenderTime.
        guard
            let renderTime = activePlayer.lastRenderTime,
            renderTime.isSampleTimeValid
        else {
            return currentActiveFileRemainingRenderFrameCount()
        }
        return AVAudioFramePositionValue(renderTime.sampleTime) + currentActiveFileRemainingRenderFrameCount()
    }

    private func currentActiveSourceFrame() -> AVAudioFramePositionValue {
        guard
            let renderTime = activePlayer.lastRenderTime,
            let playerTime = activePlayer.playerTime(forNodeTime: renderTime)
        else {
            return lastScheduledFrame
        }
        let sourceFrameOffset = renderedFramesToSourceFrames(
            AVAudioFramePositionValue(playerTime.sampleTime),
            sourceSampleRate: lastScheduledSourceSampleRate
        )
        return lastScheduledFrame + sourceFrameOffset
    }

    private func currentActiveRenderFrame() -> AVAudioFramePositionValue {
        guard
            let renderTime = activePlayer.lastRenderTime,
            let playerTime = activePlayer.playerTime(forNodeTime: renderTime)
        else {
            return sourceFramesToRenderFrames(lastScheduledFrame, sourceSampleRate: lastScheduledSourceSampleRate)
        }
        return AVAudioFramePositionValue(playerTime.sampleTime)
    }

    private func renderedFramesToSourceFrames(_ frames: AVAudioFramePositionValue, sourceSampleRate: Double) -> AVAudioFramePositionValue {
        AVAudioFramePositionValue((Double(frames) * sourceSampleRate / processingFormat.sampleRate).rounded(.towardZero))
    }

    private func sourceFramesToRenderFrames(_ frames: AVAudioFramePositionValue, sourceSampleRate: Double) -> AVAudioFramePositionValue {
        AVAudioFramePositionValue((Double(frames) * processingFormat.sampleRate / sourceSampleRate).rounded(.toNearestOrAwayFromZero))
    }

    private func syncOnQueue<T>(_ operation: () throws -> T) rethrows -> T {
        try queue.sync(execute: operation)
    }

    private func asyncOnQueue<T>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func asyncOnQueue<T>(_ operation: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: operation())
            }
        }
    }

    private func asyncOnQueueWithoutResult(_ operation: @escaping @Sendable () -> Void) async {
        await asyncOnQueue(operation)
    }

    private final class ScheduledAudioStream: @unchecked Sendable {
        private let file: AVAudioFile
        private let player: AVAudioPlayerNode
        private let processingFormat: AVAudioFormat
        let sourceFrameLength: AVAudioFramePositionValue
        let sourceSampleRate: Double
        private let maxReadAheadBufferCount: Int
        private let enqueueOnEngineQueue: (@escaping @Sendable () -> Void) -> Void
        private let convertBuffer: (AVAudioFile, AVAudioFrameCount) throws -> AVAudioPCMBuffer?
        private let onFinalBufferConsumed: () -> Void
        private var scheduledBufferCount = 0
        private var didReachEndOfFile = false

        private(set) var maxObservedScheduledBufferCount = 0

        init(
            file: AVAudioFile,
            player: AVAudioPlayerNode,
            processingFormat: AVAudioFormat,
            sourceFrameLength: AVAudioFramePositionValue,
            sourceSampleRate: Double,
            maxReadAheadBufferCount: Int,
            enqueueOnEngineQueue: @escaping (@escaping @Sendable () -> Void) -> Void,
            convertBuffer: @escaping (AVAudioFile, AVAudioFrameCount) throws -> AVAudioPCMBuffer?,
            onFinalBufferConsumed: @escaping () -> Void
        ) {
            self.file = file
            self.player = player
            self.processingFormat = processingFormat
            self.sourceFrameLength = sourceFrameLength
            self.sourceSampleRate = sourceSampleRate
            self.maxReadAheadBufferCount = maxReadAheadBufferCount
            self.enqueueOnEngineQueue = enqueueOnEngineQueue
            self.convertBuffer = convertBuffer
            self.onFinalBufferConsumed = onFinalBufferConsumed
        }

        func scheduleMoreBuffers() throws {
            while scheduledBufferCount < maxReadAheadBufferCount, file.framePosition < file.length {
                let remainingFrames = AVAudioFrameCount(file.length - file.framePosition)
                let frameCount = min(AudioEngineController.scheduledChunkFrameCount, remainingFrames)
                let isFinalBuffer = AVAudioFramePosition(file.framePosition) + AVAudioFramePosition(frameCount) >= file.length
                guard let buffer = try convertBuffer(file, frameCount) else {
                    break
                }

                scheduledBufferCount += 1
                maxObservedScheduledBufferCount = max(maxObservedScheduledBufferCount, scheduledBufferCount)
                if isFinalBuffer {
                    didReachEndOfFile = true
                }

                player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.enqueueOnEngineQueue { [weak self] in
                        guard let self else {
                            return
                        }
                        self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
                        do {
                            try self.scheduleMoreBuffers()
                        } catch {
                            return
                        }
                        if isFinalBuffer, self.didReachEndOfFile, self.scheduledBufferCount == 0 {
                            self.onFinalBufferConsumed()
                        }
                    }
                }
            }
        }
    }

    private enum PlayerRole {
        case primary
        case preBuffer
    }
}
