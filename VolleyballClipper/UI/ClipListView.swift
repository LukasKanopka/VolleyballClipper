import AVFoundation
import SwiftUI

struct ClipListView: View {
    let clips: [CMTimeRange]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(clips.enumerated()), id: \.offset) { idx, range in
                let start = range.start.seconds
                let end = range.end.seconds
                let dur = range.duration.seconds
                HStack {
                    Text("Clip \(idx + 1)")
                        .frame(width: 60, alignment: .leading)
                    Text("\(start, specifier: "%.2f")s → \(end, specifier: "%.2f")s")
                        .font(.callout)
                    Spacer()
                    Text("\(dur, specifier: "%.2f")s")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
    }
}

