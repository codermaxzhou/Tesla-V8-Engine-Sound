import SwiftUI

struct DriveLoggingView: View {
    let controller: SimulationController
    @State private var exportError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Start Logging", action: controller.startLogging).disabled(controller.logger.isLogging)
                Button("Stop Logging", action: controller.stopLogging).disabled(!controller.logger.isLogging)
            }
            LabeledContent("Samples", value: "\(controller.logger.records.count) / \(controller.logger.maximumRecords)")
            Text(controller.logger.status).font(.caption).foregroundStyle(.secondary)
            Button("Export CSV", systemImage: "square.and.arrow.up") {
                do { try controller.logger.exportCSV(); exportError = nil }
                catch { exportError = "CSV export failed: \(error.localizedDescription)" }
            }.disabled(controller.logger.records.isEmpty || controller.logger.isLogging)
            if let url = controller.logger.exportURL {
                ShareLink("Share CSV / Save to Files", item: url)
            }
            if let exportError { Text(exportError).foregroundStyle(.red) }
            Text("Logs stay in memory until exported. Starting a new session replaces the previous log. Backgrounding stops logging; export before closing the app.")
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(!controller.canCalibrate)
    }
}
