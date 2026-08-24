import SwiftUI

/// History list (PRD §7.4 / AC-HS-*). Pinned favorites (★) on top, then the
/// rolling recent list. Tapping a row refills the Chinese and re-translates (FIX-7);
/// the ★ button pins/unpins.
struct HistoryPanel: View {
    @EnvironmentObject var vm: TranslatorViewModel
    @EnvironmentObject var history: HistoryStore
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                Text("历史记录")
                    .font(DS.Font.h4())
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer(minLength: DS.Space.xs)
                Button("清空最近") { history.clear() }
                    .buttonStyle(DSSecondaryButtonStyle())
                    .fixedSize()
                    .disabled(history.items.isEmpty)
                Button("返回") { onClose() }
                    .buttonStyle(DSSecondaryButtonStyle())
                    .fixedSize()
            }
            .padding(.horizontal, DS.Space.md).padding(.vertical, DS.Space.sm)
            Divider()

            if history.favorites.isEmpty && history.items.isEmpty {
                Spacer()
                VStack(spacing: DS.Space.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("暂无历史记录")
                        .font(DS.Font.body())
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
            } else {
                List {
                    if !history.favorites.isEmpty {
                        Section("★ 收藏（置顶固定）") {
                            ForEach(history.favorites) { item in
                                HistoryRow(item: item,
                                           isFavorite: true,
                                           showDelete: false,
                                           onTap: { vm.applyHistory(item) },
                                           onToggleFavorite: { history.toggleFavorite(item) },
                                           onDelete: {})
                            }
                        }
                    }
                    Section("最近") {
                        if history.items.isEmpty {
                            Text("暂无最近记录")
                                .font(DS.Font.caption())
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                        ForEach(history.items) { item in
                            HistoryRow(item: item,
                                       isFavorite: false,
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
    let showDelete: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            // ★ favorite toggle
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? DS.Color.warning : DS.Color.textSecondary)
            }
            .buttonStyle(DSIconButtonStyle(size: 22))
            .opacity(isFavorite ? 1 : (hovering ? 1 : 0.5))
            .help(isFavorite ? "取消收藏" : "收藏（置顶固定）")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.sourceText)
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)
                Text("→ \(AppLanguage.named(item.targetLanguage).displayName)  ·  \(item.systemTranslation)")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.xs)
            if showDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(DS.Color.danger)
                }
                .buttonStyle(DSIconButtonStyle(size: 22))
                .opacity(hovering ? 1 : 0.35)
                .help("删除这条")
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.sm)
        .dsCard(hovering ? DS.Color.cardElevated : Color.clear, stroke: hovering ? DS.Color.stroke : Color.clear)
        .contentShape(DS.cardShape)
        .onTapGesture { onTap() }
        .onHover { hovering = $0 }
        .padding(.vertical, 2)
    }
}
