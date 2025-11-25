import SwiftUI
import AVFoundation
import AudioToolbox

final class DrumGateAudioUnitFactory: AUViewController, AUAudioUnitFactory {
    private var audioUnit: DrumGateAudioUnit?
    
    func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try DrumGateAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = unit
        return unit
    }
    
    override func loadView() {
        view = NSView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let audioUnit, let viewModel = DrumGateViewModel(audioUnit: audioUnit) else {
            let fallback = Text("Drum Gate Audio Unit not available.")
                .frame(minWidth: 320, minHeight: 200)
            let hosting = NSHostingView(rootView: fallback)
            view.addSubview(hosting)
            hosting.frame = view.bounds
            hosting.autoresizingMask = [.width, .height]
            return
        }
        let hosting = NSHostingView(rootView: DrumGateView(viewModel: viewModel))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}
