import Foundation
import Observation
import SwiftData

/// 部屋作成画面の入力状態と保存処理を持つViewModelです。
@Observable
final class RoomCreationViewModel {
    var name = ""
    var validationMessage: String?

    var canSave: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func createRoom(in modelContext: ModelContext) -> Room? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false else {
            validationMessage = "部屋名を入力してください。"
            return nil
        }

        let room = Room(
            name: trimmedName,
            displayOrder: nextDisplayOrder(in: modelContext)
        )
        modelContext.insert(room)

        do {
            try modelContext.save()
            return room
        } catch {
            validationMessage = "保存に失敗しました。もう一度試してください。"
            return nil
        }
    }

    private func nextDisplayOrder(in modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Room>(sortBy: [SortDescriptor(\Room.displayOrder, order: .reverse)])
        let rooms = (try? modelContext.fetch(descriptor)) ?? []
        return (rooms.first?.displayOrder ?? -1) + 1
    }
}
