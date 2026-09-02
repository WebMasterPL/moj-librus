import SwiftUI

struct GradeSimulatorView: View {
    let subjectName: String
    let realGrades: [GradeItem]

    @Environment(\.dismiss) private var dismiss
    @State private var hypotheticals: [GradeMath.HypotheticalGrade] = []
    @State private var newValue = 5.0
    @State private var newWeight = 1.0

    private var currentAverage: Double? { GradeMath.weightedAverage(realGrades) }
    private var projected: Double? {
        GradeMath.projectedAverage(real: realGrades, adding: hypotheticals)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Średnia teraz") {
                        Text(GradeMath.format(currentAverage))
                            .foregroundStyle(gradeColor(for: currentAverage))
                    }
                    LabeledContent("Średnia po zmianach") {
                        Text(GradeMath.format(projected))
                            .font(.headline)
                            .foregroundStyle(gradeColor(for: projected))
                    }
                }

                Section("Dodaj hipotetyczną ocenę") {
                    Stepper(value: $newValue, in: 1...6, step: 0.25) {
                        HStack {
                            Text("Ocena")
                            Spacer()
                            Text(String(format: "%.2f", newValue)).foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $newWeight, in: 1...10, step: 1) {
                        HStack {
                            Text("Waga")
                            Spacer()
                            Text(String(format: "%.0f", newWeight)).foregroundStyle(.secondary)
                        }
                    }
                    Button("Dodaj") {
                        hypotheticals.append(.init(value: newValue, weight: newWeight))
                    }
                }

                if !hypotheticals.isEmpty {
                    Section("Hipotetyczne oceny") {
                        ForEach(hypotheticals) { h in
                            HStack {
                                Text(String(format: "%.2f", h.value))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(gradeColor(for: h.value))
                                Text("waga \(String(format: "%.0f", h.weight))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { hypotheticals.remove(atOffsets: $0) }
                        Button("Wyczyść", role: .destructive) { hypotheticals.removeAll() }
                    }
                }

                Section("Ile potrzebuję?") {
                    ForEach([Double(5), 4.5, 4, 3.5, 3], id: \.self) { target in
                        if let needed = GradeMath.neededGrade(real: realGrades, weight: newWeight, target: target) {
                            LabeledContent("Na średnią \(String(format: "%.1f", target))") {
                                Text(String(format: "%.2f", needed))
                                    .foregroundStyle(gradeColor(for: needed))
                            }
                        }
                    }
                    Text("Przy jednej ocenie o wadze \(String(format: "%.0f", newWeight)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(subjectName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
        }
    }
}
