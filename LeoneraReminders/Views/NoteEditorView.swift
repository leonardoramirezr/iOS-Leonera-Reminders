import SwiftUI
import UIKit

/// The note of a reminder on a screen of its own, with nothing but its text. There is no «Guardar»: the presenter
/// saves every change as it is typed. While the keyboard is up, a microphone above it dictates text where the
/// cursor is.
struct NoteEditorView: View {
    @Binding var note: String

    @Environment(GroqKeyStore.self) private var keyStore

    @State private var dictation = DictationSession()
    @State private var textViewProxy = NoteTextViewProxy()
    @State private var isEditing = false
    @State private var showingAssistantSettings = false

    var body: some View {
        NoteTextView(text: $note, isEditing: $isEditing, proxy: textViewProxy)
            .overlay(alignment: .topLeading) {
                if note.isEmpty {
                    Text("Escribe una nota")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, NoteTextView.verticalInset)
                        .padding(.leading, NoteTextView.horizontalInset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if showsDictationBar {
                        NoteDictationBar(
                            session: dictation,
                            onStart: startDictation,
                            onFinish: finishDictation,
                            onRetry: retryDictation
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                // Only the bar animates, not the text above it.
                .animation(.snappy, value: showsDictationBar)
            }
            .navigationTitle("Nota")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingAssistantSettings) {
                AssistantSettingsView()
            }
            .onChange(of: dictation.recorder.reachedLimit) { _, reached in
                if reached { finishDictation() }
            }
            .onDisappear {
                dictation.cancel()
            }
    }

    /// The bar sits above the keyboard, so it shows only while the keyboard does. A dictation in progress keeps it
    /// even if the keyboard is lowered, so it can still be finished or discarded.
    private var showsDictationBar: Bool {
        isEditing || dictation.phase != .idle
    }

    /// Dictation needs the Groq key; without it the microphone leads to where it is added.
    private func startDictation() {
        guard keyStore.hasKey else {
            showingAssistantSettings = true
            return
        }
        Task { await dictation.start() }
    }

    private func finishDictation() {
        Task {
            if let text = await dictation.finish() { textViewProxy.insertAtCursor(text) }
        }
    }

    private func retryDictation() {
        Task {
            if let text = await dictation.retry() { textViewProxy.insertAtCursor(text) }
        }
    }
}

// MARK: - Dictation bar

/// The bar above the keyboard, in the style of the Claude app: a microphone on the right that, while recording,
/// becomes a capsule with the voice's waveform, a button to discard the recording and one to turn it into text.
private struct NoteDictationBar: View {
    let session: DictationSession
    let onStart: () -> Void
    let onFinish: () -> Void
    let onRetry: () -> Void

    @Environment(\.openURL) private var openURL

    private static let controlSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if session.phase == .idle, let error = session.error {
                errorRow(error)
            }
            switch session.phase {
            case .idle:
                microphoneButton
            case .recording:
                recordingCapsule
            case .transcribing:
                transcribingCapsule
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .animation(.snappy, value: session.phase)
    }

    private var microphoneButton: some View {
        Button(action: onStart) {
            Image(systemName: "mic")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: Self.controlSize, height: Self.controlSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Dictar")
        .transition(.scale.combined(with: .opacity))
    }

    private var recordingCapsule: some View {
        HStack(spacing: 10) {
            discardButton
            DictationWaveform(recorder: session.recorder)
            ElapsedText(since: session.recorder.startedAt)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Button(action: onFinish) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.brand, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Terminar y escribir el texto")
        }
        .modifier(DictationCapsule())
    }

    private var transcribingCapsule: some View {
        HStack(spacing: 10) {
            discardButton
            ProgressView()
            Text("Convirtiendo a texto…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .modifier(DictationCapsule())
    }

    /// Discards the recording (or the text it is being turned into) without writing anything.
    private var discardButton: some View {
        Button {
            session.cancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Descartar grabación")
    }

    /// Why the last dictation wrote nothing, with «Reintentar» when the recording was kept or the way to the
    /// Settings app when the microphone is not allowed, and a button to put it away.
    private func errorRow(_ error: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if session.needsMicrophonePermission {
                Button("Abrir Configuración") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.footnote.weight(.semibold))
            } else if session.canRetry {
                Button("Reintentar", action: onRetry)
                    .font(.footnote.weight(.semibold))
            }
            Button {
                session.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar aviso")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// The glass capsule that holds the recording and transcribing controls, as wide as the bar.
private struct DictationCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .glassEffect(.regular, in: .capsule)
            .transition(.scale(scale: 0.9, anchor: .trailing).combined(with: .opacity))
    }
}

/// The level of the voice over the last seconds as bars that scroll from right to left, the newest on the right.
private struct DictationWaveform: View {
    let recorder: AudioRecorder

    @State private var samples: [Double] = []

    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2
    private static let maxSamples = 200
    private static let sampleInterval: Duration = .milliseconds(70)

    var body: some View {
        // Read here so a new sample redraws the canvas.
        let levels = samples
        Canvas { context, size in
            let step = Self.barWidth + Self.barSpacing
            let visible = Int(size.width / step)
            for (offset, level) in levels.suffix(visible).reversed().enumerated() {
                let height = max(Self.barWidth, size.height * level)
                let rect = CGRect(
                    x: size.width - CGFloat(offset + 1) * step + Self.barSpacing,
                    y: (size.height - height) / 2,
                    width: Self.barWidth,
                    height: height
                )
                context.fill(Path(roundedRect: rect, cornerRadius: Self.barWidth / 2), with: .color(.primary))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .task {
            while !Task.isCancelled {
                samples.append(Self.barHeight(for: recorder.level))
                if samples.count > Self.maxSamples { samples.removeFirst(samples.count - Self.maxSamples) }
                try? await Task.sleep(for: Self.sampleInterval)
            }
        }
        .accessibilityHidden(true)
    }

    /// `level` goes from 0 (-50 dB) to 1 (0 dB). Below -40 dB is silence, a dot; a normal voice fills about half.
    private static func barHeight(for level: Double) -> Double {
        min(max((level - 0.2) / 0.7, 0), 1)
    }
}

// MARK: - Text view

/// Lets the note screen reach its text view, to write dictated text where the cursor is.
@MainActor
final class NoteTextViewProxy {
    fileprivate weak var textView: UITextView?

    /// Inserts `dictated` at the cursor, in place of the selected text if there is any, separated by spaces from
    /// the words around it. The cursor ends up after it, and the change can be undone like typing.
    func insertAtCursor(_ dictated: String) {
        guard let textView else { return }
        textView.unmarkText()
        let text = (textView.text ?? "") as NSString
        var range = textView.selectedRange
        if range.location == NSNotFound || NSMaxRange(range) > text.length {
            range = NSRange(location: text.length, length: 0)
        }
        let insertion = NoteDictation.insertion(
            of: dictated,
            characterBefore: text.substring(to: range.location).last,
            characterAfter: text.substring(from: NSMaxRange(range)).first
        )
        guard !insertion.isEmpty,
              let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end)
        else { return }
        textView.replace(textRange, withText: insertion)
        textView.selectedRange = NSRange(location: range.location + (insertion as NSString).length, length: 0)
        // Reported by hand, since UIKit may not tell the delegate about a change made in code.
        textView.delegate?.textViewDidChange?(textView)
        textView.scrollRangeToVisible(textView.selectedRange)
    }
}

/// A plain `UITextView`: unlike `TextEditor`, it tells where the cursor is, so dictated text goes there.
private struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let proxy: NoteTextViewProxy

    static let horizontalInset: CGFloat = 16
    static let verticalInset: CGFloat = 12

    func makeUIView(context: Context) -> NoteUITextView {
        let textView = NoteUITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(
            top: Self.verticalInset, left: Self.horizontalInset, bottom: Self.verticalInset, right: Self.horizontalInset
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.accessibilityLabel = String(localized: "Nota")
        textView.text = text
        // Like opening a note to keep writing it: the cursor starts at the end.
        textView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        proxy.textView = textView
        return textView
    }

    func updateUIView(_ textView: NoteUITextView, context: Context) {
        context.coordinator.parent = self
        proxy.textView = textView
        if textView.text != text { textView.text = text }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteTextView

        init(parent: NoteTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let text = textView.text ?? ""
            if parent.text != text { parent.text = text }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isEditing { parent.isEditing = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isEditing { parent.isEditing = false }
        }
    }
}

/// Shows the keyboard as soon as the screen appears and keeps the cursor in sight when the keyboard makes the
/// text view shorter.
private final class NoteUITextView: UITextView {
    private var focusesOnAppear = true
    private var lastSize: CGSize = .zero

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, focusesOnAppear else { return }
        focusesOnAppear = false
        // Outside the layout pass that put the view on screen.
        Task { [weak self] in _ = self?.becomeFirstResponder() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        if isFirstResponder { scrollRangeToVisible(selectedRange) }
    }
}
