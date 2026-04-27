import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = ReaderViewModel()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                Image(uiImage: model.renderImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .allowsHitTesting(false)

                Color.clear
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(touchGesture)

                readerChrome
                    .opacity(model.chromeVisible || model.settingsVisible || model.actionsVisible ? 1 : 0)
                    .allowsHitTesting(model.chromeVisible || model.settingsVisible || model.actionsVisible)
                    .animation(.easeInOut(duration: 0.18), value: model.chromeVisible)
                    .animation(.easeInOut(duration: 0.18), value: model.settingsVisible)
                    .animation(.easeInOut(duration: 0.18), value: model.actionsVisible)

                if model.actionsVisible {
                    actionsPanel
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                if model.settingsVisible {
                    settingsPanel
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(width: size.width, height: size.height)
            .onAppear { model.setViewportSize(size) }
            .onChange(of: size) { _, newSize in
                model.setViewportSize(newSize)
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
        .ignoresSafeArea(.all)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }

    private var readerChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                iconButton("line.3.horizontal", action: model.openActionsPanel)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.bookTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(model.chromeSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                ProgressView(value: Double(model.progressPercent), total: 100)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                    .tint(.red)

                iconButton("gearshape", action: model.openSettingsPanel)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.76), Color.black.opacity(0.42), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 82),
                alignment: .top
            )

            Spacer()
        }
    }

    private var actionsPanel: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    panelHeader(title: "Reader", icon: "line.3.horizontal")

                    Button(action: model.beginImport) {
                        Label("Import from Files", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PanelButtonStyle())

                    Button(action: model.restartBook) {
                        Label("Restart Book", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(PanelButtonStyle())

                    sectionTitle("Chapters")
                    ForEach(model.chapterRows) { row in
                        Button {
                            model.selectChapter(row)
                        } label: {
                            HStack {
                                Text(row.title)
                                    .lineLimit(1)
                                Spacer()
                                if row.isCurrent {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(PanelButtonStyle(isSelected: row.isCurrent))
                    }

                    sectionTitle("Library")
                    ForEach(model.records) { record in
                        Button {
                            model.selectBook(record)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                Text(recordSubtitle(record))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PanelButtonStyle())
                    }
                }
                .padding(18)
            }
            .frame(width: 320)
            .frame(maxHeight: .infinity)
            .background(panelBackground)

            Spacer()
        }
        .padding(.leading, 20)
        .padding(.top, 74)
        .padding(.bottom, 18)
    }

    private var settingsPanel: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    panelHeader(title: "Settings", icon: "gearshape")

                    settingsSection("Display") {
                        Picker("Theme", selection: $model.settings.theme) {
                            ForEach(ThemeMode.allCases, id: \.self) { theme in
                                Text(theme.label).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Phantom words", isOn: $model.settings.phantomWordsEnabled)

                        Picker("Font size", selection: $model.settings.fontSizeLevel) {
                            ForEach(ReaderSettings.readerFontSizeLabels.indices, id: \.self) { index in
                                Text(ReaderSettings.readerFontSizeLabels[index]).tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    settingsSection("Typography") {
                        typographyPreview

                        Stepper("Tracking: \(signed(model.settings.typography.trackingPx)) px", value: $model.settings.typography.trackingPx, in: -2...3)
                        Stepper("Anchor: \(model.settings.typography.anchorPercent)%", value: $model.settings.typography.anchorPercent, in: 0...100)
                        Stepper("Guide width: \(model.settings.typography.guideHalfWidth) px", value: $model.settings.typography.guideHalfWidth, in: 12...30, step: 2)
                        Stepper("Guide gap: \(model.settings.typography.guideGap) px", value: $model.settings.typography.guideGap, in: 2...8)

                        Button("Reset Typography", action: model.resetTypography)
                            .buttonStyle(PanelButtonStyle())
                    }

                    settingsSection("Pacing") {
                        scalePicker("Long words", selection: $model.settings.pacingLongWordLevelIndex)
                        scalePicker("Complexity", selection: $model.settings.pacingComplexWordLevelIndex)
                        scalePicker("Acronyms/Jargon", selection: $model.settings.pacingJargonLevelIndex)
                        scalePicker("Punctuation", selection: $model.settings.pacingPunctuationLevelIndex)
                        scalePicker("Phrases/Clauses", selection: $model.settings.pacingPhraseLevelIndex)

                        Button("Reset Pacing", action: model.resetPacing)
                            .buttonStyle(PanelButtonStyle())
                    }
                }
                .padding(18)
            }
            .frame(width: 390)
            .frame(maxHeight: .infinity)
            .background(panelBackground)
        }
        .padding(.trailing, 20)
        .padding(.top, 74)
        .padding(.bottom, 18)
    }

    private var typographyPreview: some View {
        HStack(spacing: 12) {
            ForEach(model.typographySamples.prefix(5), id: \.self) { sample in
                Text(sample)
                    .font(.system(size: 13, weight: sample == "HTTP/2" ? .bold : .regular, design: .rounded))
                    .foregroundStyle(sample == "HTTP/2" ? .red : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(white: 0.08).opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .foregroundStyle(.white)
        .tint(.red)
    }

    private func panelHeader(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Spacer()
            Button(action: model.closePanels) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func scalePicker(_ title: String, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Picker(title, selection: selection) {
                ForEach(ReaderSettings.pacingScaleLabels.indices, id: \.self) { index in
                    Text(ReaderSettings.pacingScaleLabels[index]).tag(index)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func recordSubtitle(_ record: BookRecord) -> String {
        let percent = record.wordCount > 1 ? "\((record.currentWordIndex * 100) / max(1, record.wordCount - 1))%" : "0%"
        return [record.author, percent].filter { !$0.isEmpty }.joined(separator: " - ")
    }

    private func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    private var touchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                model.touchChanged(startLocation: value.startLocation, location: value.location, translation: value.translation)
            }
            .onEnded { value in
                model.touchEnded(startLocation: value.startLocation, location: value.location, translation: value.translation)
            }
    }
}

private struct PanelButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(background(configuration: configuration))
            )
    }

    private func background(configuration: Configuration) -> Color {
        if configuration.isPressed { return Color.white.opacity(0.20) }
        if isSelected { return Color.red.opacity(0.34) }
        return Color.white.opacity(0.08)
    }
}
