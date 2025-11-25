import AVFoundation
import AudioToolbox
import DrumGateCore

final class DrumGateAudioUnit: AUAudioUnit {
    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private let parameterTreeInternal: AUParameterTree
    private let inputBusArray: AUAudioUnitBusArray
    private let outputBusArray: AUAudioUnitBusArray
    
    private struct RenderState {
        var processor = GateProcessor()
        var settings = GateSettings(threshold: -24, attack: 0.001, release: 0.12, active: true)
        var sampleRate: Double = 44_100
        var channelCount: AVAudioChannelCount = 2
    }
    
    private let statePointer: UnsafeMutablePointer<RenderState>
    
    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        
        inputBus = try AUAudioUnitBus(format: defaultFormat)
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        parameterTreeInternal = DrumGateParameters.buildTree()
        statePointer = .allocate(capacity: 1)
        statePointer.initialize(to: RenderState())
        
        super.init(componentDescription: componentDescription, options: options)
        
        maximumFramesToRender = 4_096
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
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
        parameterTreeInternal
    }
    
    override var outputProvider: AUInternalRenderBlock? {
        internalRenderBlock
    }
    
    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        guard let format = inputBus.format else {
            throw AUAudioUnitError(.formatNotSupported)
        }
        outputBus.format = format
        statePointer.pointee.sampleRate = format.sampleRate
        statePointer.pointee.channelCount = format.channelCount
        _ = statePointer.pointee.processor.reconfigure(
            gate: statePointer.pointee.settings,
            sampleRate: Float(format.sampleRate),
            profile: nil
        )
    }
    
    override var internalRenderBlock: AUInternalRenderBlock {
        let state = statePointer
        let parameterTree = parameterTreeInternal
        let thresholdParam = parameterTree.parameter(withAddress: DrumGateParameterAddress.threshold.rawValue)!
        let attackParam = parameterTree.parameter(withAddress: DrumGateParameterAddress.attack.rawValue)!
        let releaseParam = parameterTree.parameter(withAddress: DrumGateParameterAddress.release.rawValue)!
        let bypassParam = parameterTree.parameter(withAddress: DrumGateParameterAddress.bypass.rawValue)!
        
        return { _, _, frameCount, outputBusNumber, outputData, _, pullInputBlock in
            guard outputBusNumber == 0 else { return kAudioUnitErr_InvalidElement }
            guard let outputData else { return kAudioUnitErr_NoConnection }
            guard let pullInputBlock else { return kAudioUnitErr_NoConnection }
            
            let status = pullInputBlock(nil, nil, frameCount, 0, outputData)
            guard status == noErr else { return status }
            
            var settings = state.pointee.settings
            settings.threshold = thresholdParam.value
            settings.attack = attackParam.value
            settings.release = releaseParam.value
            settings.active = bypassParam.value < 0.5
            
            if settings != state.pointee.settings {
                state.pointee.settings = settings
                _ = state.pointee.processor.reconfigure(
                    gate: settings,
                    sampleRate: Float(state.pointee.sampleRate),
                    profile: nil
                )
            }
            
            guard settings.active else {
                return noErr
            }
            
            let bufferList = UnsafeMutableAudioBufferListPointer(outputData)
            state.pointee.processor.process(
                bufferList: bufferList,
                frameCount: Int(frameCount)
            )
            
            return noErr
        }
    }
}
