import KumquatCore
import PDFKit
import SwiftUI

/// Reorganize pages: reorder by dragging, rotate, delete. Emits the "2:90, 1" order string the tool takes.
struct PDFPagesView: View {
    struct Page: Identifiable, Equatable { let id: Int; var rotation = 0; let thumbnail: NSImage }

    let url: URL
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var pages: [Page]
    @State private var selection: Set<Int> = []

    init(url: URL, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.url = url; self.onSave = onSave; self.onCancel = onCancel
        let doc = PDFDocument(url: url)
        _pages = State(initialValue: (0..<(doc?.pageCount ?? 0)).compactMap { i in
            doc?.page(at: i).map { Page(id: i, thumbnail: $0.thumbnail(of: NSSize(width: 120, height: 160), for: .cropBox)) }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drag pages to reorder. Select to rotate or delete.").font(.callout).foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(pages) { page in
                    HStack(spacing: 14) {
                        Image(nsImage: page.thumbnail).resizable().aspectRatio(contentMode: .fit).frame(width: 60, height: 80)
                            .rotationEffect(.degrees(Double(page.rotation)))
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.separator))
                        Text("Page \(page.id + 1)").font(.body.monospacedDigit())
                        if page.rotation != 0 { Text("\(page.rotation)°").foregroundStyle(.secondary) }
                    }
                    .tag(page.id)
                }
                .onMove { pages.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { pages.remove(atOffsets: $0) }
            }
            .frame(minHeight: 360)
            HStack {
                Button { rotate(selection) } label: { Image(systemName: "rotate.right") }
                    .help("Rotate selected pages").accessibilityLabel("Rotate").disabled(selection.isEmpty)
                Button(role: .destructive) { pages.removeAll { selection.contains($0.id) }; selection = [] } label: { Image(systemName: "trash") }
                    .help("Delete selected pages").accessibilityLabel("Delete").disabled(selection.isEmpty || selection.count == pages.count)
                Button("Reverse") { pages.reverse() }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save Copy") { onSave(order) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(pages.isEmpty)
            }
        }
        .padding(16)
    }

    private var order: String {
        pages.map { $0.rotation == 0 ? "\($0.id + 1)" : "\($0.id + 1):\($0.rotation)" }.joined(separator: ", ")
    }

    private func rotate(_ ids: Set<Int>) {
        for i in pages.indices where ids.contains(pages[i].id) { pages[i].rotation = (pages[i].rotation + 90) % 360 }
    }
}
