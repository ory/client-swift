#if DEBUG
import SwiftUI

struct DeveloperMenuView: View {

    let store: NetworkHistoryStore

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [NetworkLogEntry] = []
    @AppStorage(DeveloperFlags.showTapIndicator) private var showTapIndicator = false

    var body: some View {
        NavigationStack {
            List {
                Section("Demo recording") {
                    Toggle("Show tap indicator", isOn: $showTapIndicator)
                }

                Section("Network log") {
                    if entries.isEmpty {
                        ContentUnavailableView("No requests yet", systemImage: "network")
                    } else {
                        ForEach(entries) { entry in
                            NavigationLink {
                                NetworkLogDetailView(entry: entry)
                            } label: {
                                NetworkLogRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Developer tools")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        Task {
                            await store.clear()
                            await reload()
                        }
                    }
                    .disabled(entries.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        entries = await store.snapshot()
    }
}

private struct NetworkLogRow: View {

    let entry: NetworkLogEntry

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.method)
                .font(.caption.monospaced().weight(.semibold))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.url.path().isEmpty ? entry.url.absoluteString : entry.url.path())
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(entry.isFailure ? .red : .secondary)
            }
        }
    }

    private var statusText: String {
        if let error = entry.errorDescription { return error }
        if let code = entry.statusCode { return "HTTP \(code)" }
        return "Pending…"
    }
}

private struct NetworkLogDetailView: View {

    let entry: NetworkLogEntry

    var body: some View {
        Form {
            Section("Summary") {
                LabeledContent("Method", value: entry.method)
                LabeledContent("URL", value: entry.url.absoluteString)
                LabeledContent("Status", value: entry.statusCode.map { "HTTP \($0)" } ?? "—")
                LabeledContent("Time", value: entry.date.formatted(date: .omitted, time: .standard))
                if let error = entry.errorDescription {
                    LabeledContent("Error", value: error)
                        .foregroundStyle(.red)
                }
            }

            headerSection("Request headers", entry.requestHeaders)
            bodySection("Request body", entry.requestBody)
            headerSection("Response headers", entry.responseHeaders)
            bodySection("Response body", entry.responseBody)
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: entry.curlDescription) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder
    private func headerSection(_ title: String, _ headers: [String: String]?) -> some View {
        if let headers, !headers.isEmpty {
            Section(title) {
                ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { name, value in
                    LabeledContent(name) {
                        Text(value).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bodySection(_ title: String, _ body: Data?) -> some View {
        let text = Self.prettyPrinted(body)
        if !text.isEmpty {
            Section(title) {
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    /// Pretty-prints a JSON body, falling back to the raw string, then a byte count.
    private static func prettyPrinted(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
    }
}
#endif
