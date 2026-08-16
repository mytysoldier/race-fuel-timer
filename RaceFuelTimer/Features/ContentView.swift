import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "drop.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
            Text("ランニング補給タイマー")
                .font(.title2.bold())
            Text("給水・補給の通知プランを設定してから開始できます。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}
