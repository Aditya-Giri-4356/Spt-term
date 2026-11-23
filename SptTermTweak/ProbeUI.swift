import SwiftUI
import UIKit

#if SPT_PROBE

public struct ProbePanel: View {
    @AppStorage("probe.enabled") private var probeEnabled: Bool = false
    @State private var logText: String = ""
    @State private var collapsed: Bool = false
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("Probe Active", isOn: $probeEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                Spacer()
                Button(collapsed ? "Show" : "Hide") { collapsed.toggle() }
                    .buttonStyle(.bordered)
                Button("Wipe") { spt_probe_wipe_log() }
                    .buttonStyle(.bordered)
                Button("Export") { spt_probe_export_redacted_log() }
                    .buttonStyle(.borderedProminent)
                Button("Copy") { copyTail() }
                    .buttonStyle(.bordered)
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))

            if !collapsed {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(["A", "B", "C", "D", "E", "F", "G", "H", "I"], id: \.self) { exp in
                        Button("Exp \(exp)") {
                            _ = spt_probe_run(exp)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!probeEnabled)
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))

                ScrollView {
                    Text(logText.isEmpty ? "(probe log empty)" : logText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .frame(maxHeight: 200)
                .background(Color.black.opacity(0.85))
                .cornerRadius(4)
            }
        }
        .padding(8)
        .background(Color(white: 0.12))
        .cornerRadius(6)
        .onReceive(timer) { _ in
            guard probeEnabled else { return }
            readTail()
        }
    }

    private func readTail() {
        guard let cPath = spt_probe_get_log_path() else { return }
        let path = String(cString: cPath)
        DispatchQueue.global(qos: .utility).async {
            guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return }
            defer { try? handle.close() }
            let size = handle.seekToEndOfFile()
            let readLen = min(size, 32 * 1024)
            handle.seek(toFileOffset: size - readLen)
            let data = handle.readDataToEndOfFile()
            let raw = String(decoding: data, as: UTF8.self)
            let lines = raw.components(separatedBy: "\n").suffix(300).joined(separator: "\n")
            DispatchQueue.main.async {
                self.logText = lines
            }
        }
    }

    private func copyTail() {
        guard let cPath = spt_probe_get_log_path() else { return }
        let path = String(cString: cPath)
        DispatchQueue.global(qos: .utility).async {
            guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return }
            defer { try? handle.close() }
            let size = handle.seekToEndOfFile()
            let readLen = min(size, 64 * 1024)
            handle.seek(toFileOffset: size - readLen)
            let data = handle.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                UIPasteboard.general.string = text
            }
        }
    }
}

#else

public struct ProbePanel: View {
    public init() {}
    public var body: some View {
        EmptyView()
    }
}

#endif
