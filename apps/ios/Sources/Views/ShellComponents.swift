import SwiftUI
import UIKit

enum NativeFeedback {
    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

struct NativeCircleButtonLabel: View {
    let systemName: String
    var visualSize: CGFloat = 38

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: visualSize, height: visualSize)
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle().stroke(.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.09), radius: 8, y: 3)
            .frame(width: Theme.hitMin, height: Theme.hitMin)
            .contentShape(Rectangle())
    }
}

/// Claude-app-style circular header button (36pt, raised surface fill).
struct CircleIconButton: View {
    let systemName: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button {
            NativeFeedback.lightImpact()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                NativeCircleButtonLabel(systemName: systemName)
                if badge > 0 {
                    Text(badge > 99 ? "99+" : String(badge))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Theme.mention)
                        .clipShape(Capsule())
                        .overlay(Circle().stroke(Theme.bgApp, lineWidth: 2).frame(width: 17, height: 17))
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// A pushed secondary screen (Activity, Agents, Friends, Channel info): large
/// title, a circular back button, and the app background. Keeps the native pop
/// gesture alive via the swipe-back fix below.
struct ScreenScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bgApp)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CircleIconButton(systemName: "chevron.left") { dismiss() }
                }
            }
    }
}

// Restore the interactive swipe-to-go-back gesture on screens that hide the
// default back button (we replace it with a circular one). Without this, hiding
// `navigationBarBackButton` also disables the edge-pop gesture.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
