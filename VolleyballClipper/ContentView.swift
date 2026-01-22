//
//  ContentView.swift
//  VolleyballClipper
//
//  Created by Lukas Kanopka on 1/21/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        TabView {
            ProcessView(model: model)
                .tabItem { Label("Process", systemImage: "wand.and.stars") }

            DebugView(model: model)
                .tabItem { Label("Debug", systemImage: "waveform.path.ecg") }

            BatchView(model: model)
                .tabItem { Label("Batch", systemImage: "tray.2") }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
