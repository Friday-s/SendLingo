import SwiftUI

/// History list (PRD §7.4 / AC-HS-*). Pinned favorites (★, max 3) on top, then the
/// rolling recent list. Tapping a row refills the Chinese and re-translates (FIX-7);
/// the ★ button pins/unpins.
struct HistoryPanel: View {
    @EnvironmentObject var vm: TranslatorViewModel
    @EnvironmentObject var history: HistoryStore
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("历史记录").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("清空最近") { history.clear() }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .disabled(history.items.isEmpty)
                Button("返回") { onClose() }
                    .buttonStyle(.borderless).font(.system(size: 11))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            if history.favorites.isEmpty && history.items.isEmpty {
                Spacer()
                Text("暂无历史记录").foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
            } else {
                List {
                    if !history.favorites.isEmpty {
                        Section("★ 收藏（最多 3，置顶固定）") {
                            ForEach(history.favorites) { item in
                                HistoryRow(item: item,
                                           isFavorite: true,
                                           canFavorite: true,
                                           showDelete: false,
                                           onTap: { vm.applyHistory(item) },
                                           onToggleFavorite: { history.toggleFavorite(item) },
                                           onDelete: {})
                            }
                        }
                    }
                    Section("最近") {
                        if history.items.isEmpty {
                            Text("暂无最近记录").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                        ForEach(history.items) { item in
                            HistoryRow(item: item,
                                       isFavorite: false,
                                       canFavorite: history.canAddFavorite,
                                       showDelete: true,
                                       onTap: { vm.applyHistory(item) },
                                       onToggleFavorite: { history.toggleFavorite(item) },
                                       onDelete: { history.delete(item) })
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let item: TranslationHistoryItem
    let isFavorite: Bool
    let canFavorite: Bool
    let showDelete: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // ★ favorite toggle
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!isFavorite && !canFavorite) // 收藏已满时不能再加
            .opacity(isFavorite ? 1 : (canFavorite ? (hovering ? 1 : 0.5) : 0.25))
            .help(isFavorite ? "取消收藏" : (canFavorite ? "收藏（置顶固定）" : "收藏已满（最多 3）"))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.sourceText)
                    .font(.system(size: 12)).lineLimit(2)
                Text("→ \(AppLanguage.named(item.targetLanguage).displayName)  ·  \(item.systemTranslation)")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if showDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .opacity(hovering ? 1 : 0.35)
                .help("删除这条")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering = $0 }
        .padding(.vertical, 2)
    }
}
