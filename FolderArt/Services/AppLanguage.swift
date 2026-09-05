import AppKit
import Combine

/// アプリ内の言語メニューの選択肢。rawValue は AppleLanguages に書く言語コード (String Catalog の言語と同じ)
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case ja, en, de, es, fr, ko
    case ptBR = "pt-BR"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    /// メニューの表示名。system だけ訳し、他は各言語の自称 (どの言語で起動していても同じ見た目)
    var displayName: String {
        switch self {
        case .system: return String(localized: "システムに従う")
        case .ja:     return "日本語"
        case .en:     return "English"
        case .de:     return "Deutsch"
        case .es:     return "Español"
        case .fr:     return "Français"
        case .ko:     return "한국어"
        case .ptBR:   return "Português (Brasil)"
        case .zhHant: return "繁體中文"
        }
    }
}

/// 言語の選択を UserDefaults に保存し、再起動を促す。macOS は起動中の言語切り替えを持たないので
/// AppleLanguages を書いて次回起動 (または今すぐの再起動) で反映する。
/// 起動時は自前キーだけ読む (AppleLanguages は上書きしていなくてもシステムの値が読めてしまい、
/// 「システムに従う」と区別できないため)
@MainActor
final class LanguageSetting: ObservableObject {
    static let key = "FolderArtLanguage"
    static let appleLanguagesKey = "AppleLanguages"

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            persist()
            needsRelaunch = true
        }
    }
    /// 変更後のアラート表示用。閉じれば false に戻る (再提示はしない。設定は保存済みなので次回起動で反映される)
    @Published var needsRelaunch = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selection = defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// UserDefaults は cfprefsd を介するので、set した値は plist への書き出しを待たずに新しいプロセスから読める
    private func persist() {
        if selection == .system {
            defaults.removeObject(forKey: Self.key)
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        } else {
            defaults.set(selection.rawValue, forKey: Self.key)
            defaults.set([selection.rawValue], forKey: Self.appleLanguagesKey)
        }
    }

    /// 自分をもう 1 つ起動してから終了する。起動に失敗したら終了せず onFailure に渡す
    func relaunch(onFailure: @escaping (Error) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    onFailure(error)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
