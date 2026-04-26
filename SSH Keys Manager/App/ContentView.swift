//
//  ContentView.swift
//  SSH Keys Manager
//
//  Created by Stmol on 22.04.2026.
//

import SwiftUI

struct ContentView: View {
    let model: AppModel

    var body: some View {
        AppShellView(model: model)
            .frame(minWidth: 960, minHeight: 760)
            .task {
                await model.keysCoordinator.loadIfNeeded()
                await model.configCoordinator.loadIfNeeded()
            }
    }
}

#Preview {
    ContentView(model: AppModel())
}

#Preview("Empty State") {
    ContentView(model: AppModel(keys: [], configEntries: []))
        .frame(width: 960, height: 620)
}
