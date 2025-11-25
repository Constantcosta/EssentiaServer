import Foundation
import AudioToolbox

enum DrumGateParameterAddress: AUParameterAddress {
    case threshold = 0
    case attack = 1
    case release = 2
    case bypass = 3
}

struct DrumGateParameters {
    static func buildTree() -> AUParameterTree {
        let threshold = AUParameterTree.createParameter(
            withIdentifier: "threshold",
            name: "Threshold",
            address: DrumGateParameterAddress.threshold.rawValue,
            min: -60,
            max: 0,
            unit: .decibels,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        threshold.value = -24
        
        let attack = AUParameterTree.createParameter(
            withIdentifier: "attack",
            name: "Attack",
            address: DrumGateParameterAddress.attack.rawValue,
            min: 0.0004,
            max: 0.02,
            unit: .seconds,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        attack.value = 0.001
        
        let release = AUParameterTree.createParameter(
            withIdentifier: "release",
            name: "Release",
            address: DrumGateParameterAddress.release.rawValue,
            min: 0.02,
            max: 0.4,
            unit: .seconds,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        release.value = 0.12
        
        let bypass = AUParameterTree.createParameter(
            withIdentifier: "bypass",
            name: "Bypass",
            address: DrumGateParameterAddress.bypass.rawValue,
            min: 0,
            max: 1,
            unit: .boolean,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        bypass.value = 0
        
        let tree = AUParameterTree.createTree(withChildren: [threshold, attack, release, bypass])
        return tree
    }
}
