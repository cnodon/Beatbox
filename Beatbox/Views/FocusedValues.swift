import SwiftUI

private struct BeatboxTextEditingKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var beatboxTextEditing: Bool? {
        get { self[BeatboxTextEditingKey.self] }
        set { self[BeatboxTextEditingKey.self] = newValue }
    }
}
