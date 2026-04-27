import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = ReaderViewModel()
    @GestureState private var longPressing = false
    @State private var dragActive = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                Image(uiImage: model.renderImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .simultaneousGesture(longPress)
                    .simultaneousGesture(dragGesture)
                    .onTapGesture { model.tap() }

                Button(action: model.openMenu) {
                    Color.clear.frame(width: 72, height: 54)
                }
                .buttonStyle(.plain)
            }
            .fileImporter(
                isPresented: $model.importing,
                allowedContentTypes: [.rsvp, .plainText, .text, .html, .epub, .markdownBook],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result {
                    model.importURLs(urls)
                }
            }
        }
        .background(Color.black)
        .persistentSystemOverlays(.hidden)
    }

    private var longPress: some Gesture {
        LongPressGesture(minimumDuration: 0.18)
            .updating($longPressing) { value, state, _ in
                state = value
            }
            .onChanged { _ in model.longPressChanged(true) }
            .onEnded { _ in model.longPressChanged(false) }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !dragActive {
                    dragActive = true
                    model.gestureStarted()
                }
                model.dragChanged(value.translation)
            }
            .onEnded { value in
                dragActive = false
                model.dragEnded(value.translation)
            }
    }
}
