// T3d Boy — T3d Tunes feature panel (stub; implemented in its dedicated file).
import Cocoa

final class PerformancePanel: NSView {
    private let engine: ChiptuneEngine
    private let onChange: () -> Void
    init(engine: ChiptuneEngine, onChange: @escaping () -> Void) {
        self.engine = engine
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }
}
