//
//  TinyGainAudioUnit.swift
//  Auralis
//
//  Minimal rampable gain AU with hostTime-scheduled linear ramps.
//

import AVFoundation
import AudioToolbox
import Darwin

public final class TinyGainUnit: AVAudioUnitEffect {
    private static let componentType: OSType = kAudioUnitType_Effect
    private static let componentSubType: OSType = 0x54474e31 // 'TGN1'
    private static let componentManufacturer: OSType = 0x41555241 // 'AURA'

    private static var registered: Bool = {
        let desc = AudioComponentDescription(componentType: componentType,
                                             componentSubType: componentSubType,
                                             componentManufacturer: componentManufacturer,
                                             componentFlags: 0,
                                             componentFlagsMask: 0)
        AUAudioUnit.registerSubclass(TinyGainAU.self, as: desc, name: "TinyGain", version: 1)
        return true
    }()

    public override init() {
        _ = TinyGainUnit.registered
        let desc = AudioComponentDescription(componentType: TinyGainUnit.componentType,
                                             componentSubType: TinyGainUnit.componentSubType,
                                             componentManufacturer: TinyGainUnit.componentManufacturer,
                                             componentFlags: 0,
                                             componentFlagsMask: 0)
        super.init(audioComponentDescription: desc)
    }

    // 0.0 = mute, 1.0 = unity
    public func setLinearGain(_ value: Float) {
        (self.auAudioUnit as? TinyGainAU)?.setImmediateGain(value)
    }

    public func scheduleLinearRamp(to value: Float, duration: TimeInterval, atHostTime: UInt64) {
        (self.auAudioUnit as? TinyGainAU)?.scheduleRamp(to: value, duration: duration, atHostTime: atHostTime)
    }
}

final class TinyGainAU: AUAudioUnit {
    private let gainParam: AUParameter
    private let paramTree: AUParameterTree

    // Render state
    private var currentGain: Float = 1.0
    private var rampStartHostTime: UInt64 = 0
    private var rampDuration: Double = 0.0
    private var rampStartValue: Float = 1.0
    private var rampEndValue: Float = 1.0
    private var rampActive: Bool = false

    private let stateLock = NSLock()

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        gainParam = AUParameterTree.createParameter(withIdentifier: "gain",
                                                    name: "Gain",
                                                    address: 0,
                                                    min: 0.0,
                                                    max: 1.0,
                                                    unit: .linearGain,
                                                    unitName: nil,
                                                    flags: [.flag_IsReadable, .flag_IsWritable],
                                                    valueStrings: nil,
                                                    dependentParameters: nil)
        paramTree = AUParameterTree.createTree(withChildren: [gainParam])
        try super.init(componentDescription: componentDescription, options: options)

        self.parameterTree = paramTree

        paramTree.implementorValueObserver = { [weak self] param, value in
            guard let self, param.address == 0 else { return }
            self.setImmediateGain(value)
        }
        paramTree.implementorValueProvider = { [weak self] param in
            guard let self, param.address == 0 else { return 1.0 }
            return self.currentGain
        }
        self.maximumFramesToRender = 4096
    }

    // Removed override var parameterTree

    // MARK: - Control API
    func setImmediateGain(_ value: Float) {
        stateLock.lock(); defer { stateLock.unlock() }
        currentGain = value
        rampActive = false
        gainParam.setValue(value, originator: nil)
    }

    func scheduleRamp(to value: Float, duration: TimeInterval, atHostTime: UInt64) {
        stateLock.lock(); defer { stateLock.unlock() }
        rampStartValue = currentGain
        rampEndValue = value
        rampDuration = max(0.0, duration)
        rampStartHostTime = atHostTime
        rampActive = true
    }

    // MARK: - Render
    override var internalRenderBlock: AUInternalRenderBlock {
        let render: AUInternalRenderBlock = { [weak self] (
            actionFlags,
            timestamp,
            frameCount,
            outputBusNumber,
            outputData,
            renderEvent,
            pullInputBlock
        ) -> AUAudioUnitStatus in
            guard let self else { return noErr }

            // Pull input
            var pullFlags: AudioUnitRenderActionFlags = []
            let status = pullInputBlock?( &pullFlags, timestamp, frameCount, 0, outputData ) ?? noErr
            if status != noErr { return status }

            // Snapshot state for this render quantum
            let active = self.rampActive
            var g = self.currentGain
            if active {
                let ht = timestamp.pointee.mHostTime
                let startHT = self.rampStartHostTime
                let dur = self.rampDuration
                if dur > 0, ht >= startHT {
                    let tNow = TinyGainAU.seconds(fromHostTime: ht)
                    let tStart = TinyGainAU.seconds(fromHostTime: startHT)
                    let p = max(0.0, min(1.0, (tNow - tStart) / dur))
                    g = self.rampStartValue + Float(p) * (self.rampEndValue - self.rampStartValue)
                    if p >= 1.0 {
                        self.currentGain = self.rampEndValue
                        self.rampActive = false
                    }
                } else if dur == 0, ht >= startHT {
                    g = self.rampEndValue
                    self.currentGain = g
                    self.rampActive = false
                }
            }

            let abl = outputData
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let frames = Int(frameCount)
            for buffer in buffers {
                if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    var i = 0
                    while i < frames { data[i] *= g; i += 1 }
                }
            }
            return noErr
        }
        return render
    }

    private static func seconds(fromHostTime ht: UInt64) -> Double {
        var info = mach_timebase_info_data_t(numer: 0, denom: 0)
        mach_timebase_info(&info)
        let nanos = (Double(ht) * Double(info.numer)) / Double(info.denom)
        return nanos * 1e-9
    }
}

