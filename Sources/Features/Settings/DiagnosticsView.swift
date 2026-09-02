import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(AppState.self) private var app

    @State private var results: [DiagnosticResult] = []
    @State private var running = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await runChecks() }
                } label: {
                    HStack {
                        Label("Uruchom test połączenia", systemImage: "stethoscope")
                        Spacer()
                        if running { ProgressView() }
                    }
                }
                .disabled(running)
            } footer: {
                Text("Sprawdza każdy endpoint Librusa osobno. Skopiuj raport i wyślij go, jeśli coś nie działa.")
            }

            if !results.isEmpty {
                Section {
                    ForEach(results) { r in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(r.ok ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.callout.weight(.medium))
                                Text(r.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = Diagnostics.report(results)
                        copied = true
                    } label: {
                        Label(copied ? "Skopiowano" : "Kopiuj raport", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .navigationTitle("Diagnostyka")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runChecks() async {
        running = true
        copied = false
        results = []
        defer { running = false }
        results = await Diagnostics(session: app.session).run()
    }
}
