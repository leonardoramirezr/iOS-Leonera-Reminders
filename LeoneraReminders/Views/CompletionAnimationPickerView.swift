import SwiftUI

/// The animations for a completed reminder: tapping one chooses it and plays it over the app, which can still be
/// used while it plays.
struct CompletionAnimationPickerView: View {
    @Binding var selection: CompletionAnimation

    var body: some View {
        List {
            Section {
                ForEach(CompletionAnimation.allCases) { animation in
                    Button {
                        selection = animation
                        CelebrationPresenter.shared.play(animation)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: animation.systemImage)
                                .font(.title3)
                                .foregroundStyle(Color.brand)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(animation.label)
                                    .foregroundStyle(Color.primary)
                                Text(animation.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if animation == selection {
                                Image(systemName: "checkmark").foregroundStyle(Color.brand)
                            }
                        }
                    }
                    .accessibilityAddTraits(animation == selection ? .isSelected : [])
                }
            } footer: {
                Text("Toca una animación para elegirla y verla. Mientras se ve puedes seguir usando la app; sólo los fuegos artificiales pueden impedirlo, según «Mientras se ven». Confirmar un evento del calendario no tiene animación.")
            }
        }
        .navigationTitle("Animación al completar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension CompletionAnimation {
    /// The SF Symbol shown next to the animation in Settings.
    var systemImage: String {
        switch self {
        case .fireworks: "fireworks"
        case .confetti: "party.popper"
        case .coins: "dollarsign.circle"
        case .balloons: "balloon.2"
        case .stars: "star"
        case .checkmark: "checkmark.circle"
        case .hearts: "heart"
        case .glow: "iphone.radiowaves.left.and.right"
        case .emoji: "face.smiling"
        case .off: "slash.circle"
        }
    }

    /// One line about the animation, under its name in Settings.
    var summary: String {
        switch self {
        case .fireworks: "Cohetes que estallan en el cielo, nunca iguales."
        case .confetti: "Dos cañones de papelitos desde las esquinas."
        case .coins: "Una fuente de monedas de oro que giran."
        case .balloons: "Globos de colores que suben flotando."
        case .stars: "Estrellas doradas que estallan desde el centro."
        case .checkmark: "Una palomita grande que se dibuja sola."
        case .hearts: "Corazones que suben al ritmo de un latido."
        case .glow: "Una luz de colores recorre el borde de la pantalla."
        case .emoji: "Una lluvia de emojis de fiesta."
        case .off: "Completar sólo vibra."
        }
    }
}
