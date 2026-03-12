import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var blockStore: BlockStore

    var body: some View {
        if let startupErrorMessage = blockStore.startupErrorMessage {
            ContentUnavailableView(
                "History Unavailable",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(startupErrorMessage)
            )
        } else if blockStore.recentBlocks.isEmpty {
            ContentUnavailableView(
                "No Blocks Yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("Run commands in the terminal and Tesara will capture finished command blocks here.")
            )
        } else {
            List(blockStore.recentBlocks) { block in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(block.commandText)
                            .font(.headline.monospaced())
                            .lineLimit(2)

                        Spacer()

                        Text(exitBadge(for: block.exitCode))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(exitBadgeColor(for: block.exitCode), in: Capsule())
                    }

                    Text(block.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No output" : block.outputText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(6)

                    HStack {
                        Text(block.workingDirectory)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(block.finishedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
            }
            .navigationTitle("History")
        }
    }

    private func exitBadge(for exitCode: Int?) -> String {
        guard let exitCode else {
            return "No Status"
        }

        return exitCode == 0 ? "Success" : "Exit \(exitCode)"
    }

    private func exitBadgeColor(for exitCode: Int?) -> Color {
        guard let exitCode else {
            return .gray.opacity(0.18)
        }

        return exitCode == 0 ? .green.opacity(0.18) : .red.opacity(0.18)
    }
}
