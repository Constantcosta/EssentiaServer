import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Drum Gate Host")
                .font(.title.bold())
            Text("This lightweight macOS app bundles the Drum Gate AUv3 extension. Build and run to install the Audio Unit, then load “Drum Gate” from your AU host (Logic, MainStage, GarageBand, etc.).")
                .multilineTextAlignment(.center)
                .font(.body)
            Text("Bundle ID: com.essentia.drumgate.plugin\nComponent: aufx/DGTE/ESNT")
                .font(.footnote.monospaced())
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 380, minHeight: 220)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
