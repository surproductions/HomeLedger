import SwiftData
import SwiftUI

struct AddMenuView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private struct Action: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let run: () -> Void
    }

    var body: some View {
        let actions: [Action] = [
            Action(id: "item", title: "Item", subtitle: "Photo, details & warranty", symbol: "shippingbox", tint: Theme.tintBlue) {
                if DataService(context: context).canAddAsset(entitlements: app.entitlement) { app.present(.newAsset(roomID: nil)) } else { app.present(.paywall(.unlimitedItems)) }
            },
            Action(id: "scan", title: "Scan document", subtitle: "Receipt, manual, warranty", symbol: "doc.viewfinder", tint: Theme.tintPurple) {
                app.present(.importDocument(DocumentScannerView.isAvailable ? .camera : .chooser, assetID: nil))
            },
            Action(id: "import", title: "Import file", subtitle: "PDF or image from Files", symbol: "folder", tint: Theme.tintTeal) {
                app.present(.importDocument(.chooser, assetID: nil))
            },
            Action(id: "task", title: "Maintenance task", subtitle: "One-time or recurring", symbol: "calendar.badge.plus", tint: Theme.tintOrange) {
                app.present(.newTask(assetID: nil))
            },
            Action(id: "repair", title: "Repair or service", subtitle: "Who, when and cost", symbol: "wrench.adjustable", tint: Theme.tintPink) {
                app.present(.newService(assetID: nil))
            },
            Action(id: "expense", title: "Expense", subtitle: "Any home-related cost", symbol: "creditcard", tint: Theme.tintGreen) {
                app.present(.newExpense(assetID: nil))
            }
        ]
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(actions) { action in
                        Button(action: action.run) {
                            VStack(alignment: .leading, spacing: 10) {
                                IconBadge(systemName: action.symbol, tint: action.tint, size: 42)
                                Text(action.title).font(.headline).foregroundStyle(Theme.ink)
                                Text(action.subtitle).font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                            .card(padding: 14)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("add.\(action.id)")
                    }
                }
                .padding(Theme.gutter)
            }
            .canvasBackground()
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
