//
//  RealtimeGateAudioUnit.swift
//  MacStudioServerSimulator
//
//  Lightweight in-app Audio Unit that applies the drum gate in realtime so UI tweaks are audible immediately.
//

import Foundation
import AVFoundation
import AudioToolbox

final class RealtimeGateAudioUnit: AUAudioUnit {
    enum GateParam: AUParameterAddress {
        case threshold = 0
        case attack
        case release
        case floor
        case bypass
    }
    
    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCC("dgt1"),
        componentManufacturer: fourCC("ESNT"),
        componentFlags: 0,
        componentFlagsMask: 0
    )
    
    private static var hasRegistered = false
    static func register() {
        guard !hasRegistered else { return }
        AUAudioUnit.registerSubclass(
            RealtimeGateAudioUnit.self,
            as: componentDescription,
            name: "EssentiaRealtimeGate",
            version: UInt32.max
        )
        hasRegistered = true
    }
    
    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private let parameterTreeInternal: AUParameterTree
    private lazy var inputBusArray: AUAudioUnitBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
    private lazy var outputBusArray: AUAudioUnitBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    
    private struct RenderState {
        var processor = GateProcessor()
        var settings = GateSettings()
        var profile: DrumProfile?
        var sampleRate: Double = 44_100
    }
    
    private let statePointer: UnsafeMutablePointer<RenderState>
    
    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: defaultFormat)
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        parameterTreeInternal = RealtimeGateAudioUnit.buildParameterTree()
        statePointer = .allocate(capacity: 1)
        statePointer.initialize(to: RenderState())

        try super.init(componentDescription: componentDescription, options: options)
        
        maximumFramesToRender = 4_096
    }
    
    deinit {
        statePointer.deinitialize(count: 1)
        statePointer.deallocate()
    }
    
    override var inputBusses: AUAudioUnitBusArray {
        inputBusArray
    }
    
    override var outputBusses: AUAudioUnitBusArray {
        outputBusArray
    }
    
    override var parameterTree: AUParameterTree? {
        get { parameterTreeInternal }
        set { }
    }
    
    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let format = inputBus.format
        do {
            try outputBus.setFormat(format)
        } catch {
            print("RealtimeGateAudioUnit: failed to set output format: \(error.localizedDescription)")
        }
        statePointer.pointee.sampleRate = format.sampleRate
        _ = statePointer.pointee.processor.reconfigure(
            gate: statePointer.pointee.settings,
            sampleRate: Float(format.sampleRate),
            profile: statePointer.pointee.profile
        )
    }
    
    func update(settings: GateSettings, profile: DrumProfile?) {
        statePointer.pointee.profile = profile
        statePointer.pointee.settings = settings
        setParameter(.threshold, to: settings.threshold)
        setParameter(.attack, to: settings.attack)
        setParameter(.release, to: settings.release)
        setParameter(.floor, to: settings.floorDb ?? -120)
        setParameter(.bypass, to: settings.active ? 0 : 1)
        _ = statePointer.pointee.processor.reconfigure(
            gate: settings,
            sampleRate: Float(statePointer.pointee.sampleRate),
            profile: profile
        )
    }
    
    override var internalRenderBlock: AUInternalRenderBlock {
        let state = statePointer
        let thresholdParam = parameterTreeInternal.parameter(withAddress: GateParam.threshold.rawValue)!
        let attackParam = parameterTreeInternal.parameter(withAddress: GateParam.attack.rawValue)!
        let releaseParam = parameterTreeInternal.parameter(withAddress: GateParam.release.rawValue)!
        let floorParam = parameterTreeInternal.parameter(withAddress: GateParam.floor.rawValue)!
        let bypassParam = parameterTreeInternal.parameter(withAddress: GateParam.bypass.rawValue)!
        
        return { _, _, frameCount, outputBusNumber, outputData, _, pullInputBlock in
            guard outputBusNumber == 0 else { return kAudioUnitErr_InvalidElement }
            guard let pullInputBlock else { return kAudioUnitErr_NoConnection }

            var flags = AudioUnitRenderActionFlags(rawValue: 0)
            var timestamp = AudioTimeStamp()
            let status = pullInputBlock(&flags, &timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }
            
            var settings = state.pointee.settings
            settings.threshold = thresholdParam.value
            settings.attack = attackParam.value
            settings.release = releaseParam.value
            let floorValue = floorParam.value
            settings.floorDb = floorValue <= -120 ? nil : floorValue
            settings.active = bypassParam.value < 0.5
            
            if settings != state.pointee.settings {
                state.pointee.settings = settings
                _ = state.pointee.processor.reconfigure(
                    gate: settings,
                    sampleRate: Float(state.pointee.sampleRate),
                    profile: state.pointee.profile
                )
            }
            
            let bufferList = UnsafeMutableAudioBufferListPointer(outputData)
            if settings.active {
                state.pointee.processor.process(bufferList: bufferList, frameCount: Int(frameCount))
            }
            
            return noErr
        }
    }
    
    private func setParameter(_ param: GateParam, to value: AUValue) {
        parameterTreeInternal.parameter(withAddress: param.rawValue)?.value = value
    }
    
    private static func buildParameterTree() -> AUParameterTree {
        let threshold = AUParameterTree.createParameter(
            withIdentifier: "threshold",
            name: "Threshold",
            address: GateParam.threshold.rawValue,
            min: -60,
            max: 0,
            unit: .decibels,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        let attack = AUParameterTree.createParameter(
            withIdentifier: "attack",
            name: "Attack",
            address: GateParam.attack.rawValue,
            min: 0.001,
            max: 0.5,
            unit: .seconds,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        let release = AUParameterTree.createParameter(
            withIdentifier: "release",
            name: "Release",
            address: GateParam.release.rawValue,
            min: 0.02,
            max: 1.5,
            unit: .seconds,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        let floor = AUParameterTree.createParameter(
            withIdentifier: "floor",
            name: "Floor",
            address: GateParam.floor.rawValue,
            min: -120,
            max: -6,
            unit: .decibels,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        let bypass = AUParameterTree.createParameter(
            withIdentifier: "bypass",
            name: "Bypass",
            address: GateParam.bypass.rawValue,
            min: 0,
            max: 1,
            unit: .boolean,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        let tree = AUParameterTree.createTree(withChildren: [threshold, attack, release, floor, bypass])
        threshold.value = -24
        attack.value = 0.001
        release.value = 0.02
        floor.value = -90
        bypass.value = 1 // default to bypassed
        return tree
    }
    
    private static func fourCC(_ string: String) -> OSType {
        var result: OSType = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) + OSType(char)
        }
        return result
    }
}
