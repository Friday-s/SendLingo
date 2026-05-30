import Foundation

extension Notification.Name {
    /// Posted by the panel UI (✕ button) to ask the controller to hide.
    static let optionNowHide = Notification.Name("OptionNow.hide")
    /// Posted by the panel UI to open the settings window.
    static let optionNowOpenSettings = Notification.Name("OptionNow.openSettings")
    /// Posted after ⌘C copied the translation result (to flash the "已复制" toast).
    static let optionNowResultCopied = Notification.Name("OptionNow.resultCopied")
}
