import SwiftUI

struct AudioTuningView: View {
    @Bindable var audio: EngineAudioEngine
    var includeLayerControls = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Mute Audio", isOn: $audio.tuning.isMuted)
            control("Master volume", value: $audio.tuning.masterVolume)
            if includeLayerControls {
                control("Engine volume", value: $audio.tuning.engineVolume)
                control("Intake volume", value: $audio.tuning.intakeVolume)
                control("Exhaust volume", value: $audio.tuning.exhaustVolume)
                control("Backfire amount", value: $audio.tuning.backfireAmount)
            }
            control("Shift transient volume", value: $audio.tuning.shiftTransientVolume)
            VStack(alignment: .leading) {
                LabeledContent("Audio latency compensation", value: "\(Int(audio.tuning.audioLatencyCompensationMs)) ms")
                Slider(value: $audio.tuning.audioLatencyCompensationMs, in: 0...1000, step: 10)
                    .accessibilityLabel("Audio latency compensation")
                Text("Bluetooth delay varies by hardware. Bounded RPM look-ahead may improve continuous sound response; it cannot eliminate delay or anticipate shifts. Start at 0 ms.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("CC0 V8 recordings + procedural layers • Replaceable WAV samples")
                .font(.footnote).foregroundStyle(.secondary)
            if let error = audio.errorMessage {
                Text("Audio unavailable: \(error)").font(.footnote).foregroundStyle(.red)
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func control(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%").monospacedDigit()
            }
            Slider(value: value, in: 0...1).accessibilityLabel(title)
        }
    }
}
