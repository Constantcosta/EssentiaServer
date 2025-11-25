import SwiftUI
import AudioToolbox

final class DrumGateViewModel: ObservableObject {
    @Published var threshold: Float
    @Published var attack: Float
    @Published var release: Float
    @Published var active: Bool
    
    private let parameterTree: AUParameterTree
    private let thresholdParam: AUParameter
    private let attackParam: AUParameter
    private let releaseParam: AUParameter
    private let bypassParam: AUParameter
    private var observer: AUParameterObserverToken?
    
    init?(audioUnit: AUAudioUnit) {
        guard let tree = audioUnit.parameterTree,
              let thresholdParam = tree.parameter(withAddress: DrumGateParameterAddress.threshold.rawValue),
              let attackParam = tree.parameter(withAddress: DrumGateParameterAddress.attack.rawValue),
              let releaseParam = tree.parameter(withAddress: DrumGateParameterAddress.release.rawValue),
              let bypassParam = tree.parameter(withAddress: DrumGateParameterAddress.bypass.rawValue)
        else {
            return nil
        }
        self.parameterTree = tree
        self.thresholdParam = thresholdParam
        self.attackParam = attackParam
        self.releaseParam = releaseParam
        self.bypassParam = bypassParam
        
        self.threshold = thresholdParam.value
        self.attack = attackParam.value
        self.release = releaseParam.value
        self.active = bypassParam.value < 0.5
        
        observer = tree.token(byAddingParameterObserver: { [weak self] address, value in
            DispatchQueue.main.async {
                switch address {
                case DrumGateParameterAddress.threshold.rawValue:
                    self?.threshold = value
                case DrumGateParameterAddress.attack.rawValue:
                    self?.attack = value
                case DrumGateParameterAddress.release.rawValue:
                    self?.release = value
                case DrumGateParameterAddress.bypass.rawValue:
                    self?.active = value < 0.5
                default:
                    break
                }
            }
        })
    }
    
    deinit {
        if let observer {
            parameterTree.removeParameterObserver(observer)
        }
    }
    
    func setThreshold(_ value: Float) {
        thresholdParam.value = value
    }
    
    func setAttack(_ value: Float) {
        attackParam.value = value
    }
    
    func setRelease(_ value: Float) {
        releaseParam.value = value
    }
    
    func setActive(_ isActive: Bool) {
        bypassParam.value = isActive ? 0 : 1
    }
}

struct DrumGateView: View {
    @ObservedObject var viewModel: DrumGateViewModel
    
    private func formatDb(_ value: Float) -> String {
        String(format: "%.1f dB", value)
    }
    
    private func formatMs(_ value: Float) -> String {
        String(format: "%.1f ms", value * 1000)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Drum Gate")
                        .font(.title3.bold())
                    Text("Threshold/hold tuned for drum hits; release default 120 ms.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle(isOn: Binding(
                    get: { viewModel.active },
                    set: { viewModel.setActive($0) }
                )) {
                    Text(viewModel.active ? "Active" : "Bypassed")
                        .font(.headline)
                }
                .toggleStyle(.switch)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Threshold")
                    Spacer()
                    Text(formatDb(viewModel.threshold))
                        .font(.system(.body, design: .monospaced))
                }
                Slider(
                    value: Binding(
                        get: { viewModel.threshold },
                        set: { viewModel.setThreshold($0) }
                    ),
                    in: -60...0
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Attack")
                    Spacer()
                    Text(formatMs(viewModel.attack))
                        .font(.system(.body, design: .monospaced))
                }
                Slider(
                    value: Binding(
                        get: { viewModel.attack },
                        set: { viewModel.setAttack($0) }
                    ),
                    in: 0.0004...0.02
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Release")
                    Spacer()
                    Text(formatMs(viewModel.release))
                        .font(.system(.body, design: .monospaced))
                }
                Slider(
                    value: Binding(
                        get: { viewModel.release },
                        set: { viewModel.setRelease($0) }
                    ),
                    in: 0.02...0.4
                )
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 260)
    }
}
