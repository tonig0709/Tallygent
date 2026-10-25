import SwiftUI

/// A native choice control owns the option width, never the visible field title.
/// Narrow containers fall back to a popup instead of compressing CJK into columns.
struct AdaptivePicker<Selection: Hashable, Options: View>: View {
    let title: String
    let id: String
    let selection: Binding<Selection>
    let showsTitle: Bool
    let prefersSegments: Bool
    let options: Options

    init(_ title: String, id: String, selection: Binding<Selection>, showsTitle: Bool = true, prefersSegments: Bool = true,
         @ViewBuilder options: () -> Options) {
        self.title = title
        self.id = id
        self.selection = selection
        self.showsTitle = showsTitle
        self.prefersSegments = prefersSegments
        self.options = options()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text(title)
                    .fixedSize(horizontal: true, vertical: true)
                    .controlLayoutProbe(id + ".label")
            }
            Group {
                if prefersSegments {
                    ViewThatFits(in: .horizontal) {
                        Picker(title, selection: selection) { options }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize(horizontal: true, vertical: true)
                        menu
                    }
                } else { menu }
            }
            .accessibilityLabel(title)
            .controlLayoutContainer(id + ".picker.container")
        }
        .controlLayoutContainer(id + ".container")
    }

    private var menu: some View {
        Picker(title, selection: selection) { options }
            .labelsHidden().pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Test-only geometry is opt-in. Normal App windows do not create measurement copies.
enum ControlLayoutSpace { static let name = "tallygent-content" }

struct ControlLayoutMeasurement: Equatable {
    var frame: CGRect?
    var idealSize: CGSize?
}

struct ControlLayoutPreference: PreferenceKey {
    static var defaultValue: [String: ControlLayoutMeasurement] = [:]
    static func reduce(value: inout [String: ControlLayoutMeasurement], nextValue: () -> [String: ControlLayoutMeasurement]) {
        for (id, next) in nextValue() {
            var record = value[id] ?? ControlLayoutMeasurement()
            if let frame = next.frame { record.frame = frame }
            if let ideal = next.idealSize { record.idealSize = ideal }
            value[id] = record
        }
    }
}

private struct RecordsControlLayoutKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var recordsControlLayout: Bool {
        get { self[RecordsControlLayoutKey.self] }
        set { self[RecordsControlLayoutKey.self] = newValue }
    }
}

extension View {
    func controlLayoutProbe(_ id: String) -> some View { modifier(ControlLayoutProbe(id: id, measuresIdeal: true)) }
    func controlLayoutContainer(_ id: String) -> some View { modifier(ControlLayoutProbe(id: id, measuresIdeal: false)) }
}

private struct ControlLayoutProbe: ViewModifier {
    let id: String
    let measuresIdeal: Bool
    @Environment(\.recordsControlLayout) private var enabled

    func body(content: Content) -> some View {
        if enabled {
            content
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: ControlLayoutPreference.self, value: [id: .init(
                            frame: geometry.frame(in: .named(ControlLayoutSpace.name)),
                            idealSize: measuresIdeal ? nil : geometry.size)])
                    }
                }
                .overlay {
                    if measuresIdeal {
                        content.fixedSize(horizontal: true, vertical: true).hidden()
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: ControlLayoutPreference.self,
                                        value: [id: .init(idealSize: geometry.size)])
                                }
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        } else { content }
    }
}
