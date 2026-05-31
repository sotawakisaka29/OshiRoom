import Foundation
import Observation
import SwiftData

/// 棚作成画面の入力状態と保存処理を持つViewModelです。
@Observable
final class ShelfCreationViewModel {
    var name = ""
    var selectedTemplate: ShelfTemplate = .wood
    var validationMessage: String?

    var canSave: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func createShelf(in modelContext: ModelContext) -> Shelf? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false else {
            validationMessage = "棚名を入力してください。"
            return nil
        }

        let shelf = Shelf(
            name: trimmedName,
            template: selectedTemplate,
            displayOrder: nextDisplayOrder(in: modelContext)
        )
        modelContext.insert(shelf)

        do {
            try modelContext.save()
            return shelf
        } catch {
            validationMessage = "保存に失敗しました。もう一度試してください。"
            return nil
        }
    }

    private func nextDisplayOrder(in modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.displayOrder, order: .reverse)])
        let shelves = (try? modelContext.fetch(descriptor)) ?? []
        return (shelves.first?.displayOrder ?? -1) + 1
    }
}
