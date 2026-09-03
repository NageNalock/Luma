import SwiftUI

enum LumaTheme {
    static let mercury = Color(red: 0.953, green: 0.957, blue: 0.969)
    static let pearl = Color(red: 0.988, green: 0.988, blue: 0.996)
    static let silverline = Color(red: 0.847, green: 0.859, blue: 0.894)
    static let lilacWash = Color(red: 0.933, green: 0.918, blue: 0.996)
    static let iris = Color(red: 0.463, green: 0.400, blue: 0.851)
    static let graphite = Color(red: 0.137, green: 0.141, blue: 0.173)
    static let muted = Color(red: 0.42, green: 0.43, blue: 0.49)
    static let danger = Color(red: 0.75, green: 0.22, blue: 0.32)
}

struct LumaCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(LumaTheme.pearl.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LumaTheme.silverline.opacity(0.72), lineWidth: 0.7)
            }
    }
}

extension View {
    func lumaCard() -> some View {
        modifier(LumaCardModifier())
    }
}
