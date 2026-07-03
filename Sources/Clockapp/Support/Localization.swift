import Foundation

/// Supported UI languages.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case fr, en, ptBR, it, tn
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fr: return "Français"
        case .en: return "English (US)"
        case .ptBR: return "Português (BR)"
        case .it: return "Italiano"
        case .tn: return "تونسي"
        }
    }

    var flag: String {
        switch self {
        case .fr: return "🇫🇷"
        case .en: return "🇺🇸"
        case .ptBR: return "🇧🇷"
        case .it: return "🇮🇹"
        case .tn: return "🇹🇳"
        }
    }
}

/// Keys for every translatable string. `*Fmt` keys are `String(format:)` templates.
enum LocKey {
    // Tabs / status
    case tabTracker, tabEntries, statusRunning, statusStopped
    case descPlaceholder, noProjects, project
    case autotrack, activeWindowFmt, outOfWindow
    case today, week, month, dailyGoalFmt, heatmapTitle
    case connConnecting, connError, connOffline, settings, quit, settingsWindowTitle
    // Entries
    case noEntriesToday, noDescription, runningLc, delete, save, description
    // Project picker
    case noProject, searchProject, noResult, noClient, defaultProject
    // Settings
    case tabClockify, tabSchedule, tabGoals
    case sectionConnection, apiKey, apiHelp, connect, refreshProjects, notConnected
    case useLastProject, lastUsedFmt, noneYet, projectsLoadedFmt
    case sectionDisplay, showSeconds, launchAtLogin
    case sectionHourGoals, enableGoals, dailyGoalSettingFmt, weeklyGoalSettingFmt
    case sectionReminders, notifyWindowStart, remindersHelp, sectionLanguage
    // Schedule editor
    case trackableWindows, add, scheduleHelp, noWindows, windowEditorTitle
    case name, days, startLabel, endLabel, cancel, defaultWindowName
    // Weekdays (short)
    case wdMon, wdTue, wdWed, wdThu, wdFri, wdSat, wdSun
    // Nudge
    case nudgeTitle, nudgeBodyFmt
}

enum Localization {
    /// One row = the five translations for a key.
    private struct T { let fr, en, pt, it, tn: String }

    static func string(_ key: LocKey, _ lang: AppLanguage) -> String {
        guard let t = table[key] else { return "" }
        switch lang {
        case .fr: return t.fr
        case .en: return t.en
        case .ptBR: return t.pt
        case .it: return t.it
        case .tn: return t.tn
        }
    }

    /// Localized short weekday from a Calendar weekday value (1 = Sunday ... 7 = Saturday).
    static func weekdayShort(_ calendarValue: Int, _ lang: AppLanguage) -> String {
        let key: LocKey
        switch calendarValue {
        case 1: key = .wdSun
        case 2: key = .wdMon
        case 3: key = .wdTue
        case 4: key = .wdWed
        case 5: key = .wdThu
        case 6: key = .wdFri
        default: key = .wdSat
        }
        return string(key, lang)
    }

    private static let table: [LocKey: T] = [
        .tabTracker: T(fr: "Tracker", en: "Tracker", pt: "Rastrear", it: "Traccia", tn: "تراكر"),
        .tabEntries: T(fr: "Entrées", en: "Entries", pt: "Entradas", it: "Voci", tn: "الإدخالات"),
        .statusRunning: T(fr: "En cours", en: "Running", pt: "Em curso", it: "In corso", tn: "في الخدمة"),
        .statusStopped: T(fr: "À l'arrêt", en: "Stopped", pt: "Parado", it: "Fermo", tn: "واقف"),
        .descPlaceholder: T(fr: "Description…", en: "Description…", pt: "Descrição…", it: "Descrizione…", tn: "وصف…"),
        .noProjects: T(fr: "Aucun projet — connecte Clockify", en: "No project — connect Clockify", pt: "Nenhum projeto — conecte o Clockify", it: "Nessun progetto — collega Clockify", tn: "ما فماش مشاريع — اربط Clockify"),
        .project: T(fr: "Projet", en: "Project", pt: "Projeto", it: "Progetto", tn: "مشروع"),
        .autotrack: T(fr: "Auto-suivi (déverrouillage)", en: "Auto-track (unlock)", pt: "Rastreio automático (desbloqueio)", it: "Tracciamento auto (sblocco)", tn: "تراك أوتوماتيك (كي تحلّ الماك)"),
        .activeWindowFmt: T(fr: "Plage active : %@ (%@)", en: "Active window: %@ (%@)", pt: "Janela ativa: %@ (%@)", it: "Fascia attiva: %@ (%@)", tn: "الفترة النشيطة: %@ (%@)"),
        .outOfWindow: T(fr: "Hors plage trackable", en: "Outside trackable window", pt: "Fora da janela rastreável", it: "Fuori dalla fascia", tn: "برّا من الفترة"),
        .today: T(fr: "Aujourd'hui", en: "Today", pt: "Hoje", it: "Oggi", tn: "اليوم"),
        .week: T(fr: "Semaine", en: "Week", pt: "Semana", it: "Settimana", tn: "الجمعة"),
        .month: T(fr: "Mois", en: "Month", pt: "Mês", it: "Mese", tn: "الشهر"),
        .dailyGoalFmt: T(fr: "Objectif du jour : %@ / %@", en: "Today's goal: %@ / %@", pt: "Meta do dia: %@ / %@", it: "Obiettivo di oggi: %@ / %@", tn: "هدف اليوم: %@ / %@"),
        .heatmapTitle: T(fr: "Quand tu travailles (ce mois)", en: "When you work (this month)", pt: "Quando você trabalha (este mês)", it: "Quando lavori (questo mese)", tn: "وقتاش تخدم (هالشهر)"),
        .connConnecting: T(fr: "Connexion…", en: "Connecting…", pt: "Conectando…", it: "Connessione…", tn: "يربط…"),
        .connError: T(fr: "Erreur Clockify", en: "Clockify error", pt: "Erro do Clockify", it: "Errore Clockify", tn: "غلطة Clockify"),
        .connOffline: T(fr: "Hors ligne", en: "Offline", pt: "Offline", it: "Offline", tn: "موش متصل"),
        .settings: T(fr: "Réglages", en: "Settings", pt: "Ajustes", it: "Impostazioni", tn: "الإعدادات"),
        .quit: T(fr: "Quitter", en: "Quit", pt: "Sair", it: "Esci", tn: "أخرج"),
        .settingsWindowTitle: T(fr: "Réglages Clockapp", en: "Clockapp Settings", pt: "Ajustes do Clockapp", it: "Impostazioni di Clockapp", tn: "إعدادات Clockapp"),

        .noEntriesToday: T(fr: "Aucune entrée aujourd'hui.", en: "No entries today.", pt: "Nenhuma entrada hoje.", it: "Nessuna voce oggi.", tn: "ما فماش إدخالات اليوم."),
        .noDescription: T(fr: "Sans description", en: "No description", pt: "Sem descrição", it: "Senza descrizione", tn: "بلا وصف"),
        .runningLc: T(fr: "en cours", en: "running", pt: "em curso", it: "in corso", tn: "في الخدمة"),
        .delete: T(fr: "Supprimer", en: "Delete", pt: "Excluir", it: "Elimina", tn: "افسخ"),
        .save: T(fr: "Enregistrer", en: "Save", pt: "Salvar", it: "Salva", tn: "سجّل"),
        .description: T(fr: "Description", en: "Description", pt: "Descrição", it: "Descrizione", tn: "وصف"),

        .noProject: T(fr: "Sans projet", en: "No project", pt: "Sem projeto", it: "Nessun progetto", tn: "بلا مشروع"),
        .searchProject: T(fr: "Rechercher un projet…", en: "Search a project…", pt: "Buscar um projeto…", it: "Cerca un progetto…", tn: "لوّج على مشروع…"),
        .noResult: T(fr: "Aucun résultat", en: "No result", pt: "Nenhum resultado", it: "Nessun risultato", tn: "ما فماش والو"),
        .noClient: T(fr: "Sans client", en: "No client", pt: "Sem cliente", it: "Nessun cliente", tn: "بلا كليون"),
        .defaultProject: T(fr: "Projet par défaut", en: "Default project", pt: "Projeto padrão", it: "Progetto predefinito", tn: "المشروع الافتراضي"),

        .tabClockify: T(fr: "Clockify", en: "Clockify", pt: "Clockify", it: "Clockify", tn: "Clockify"),
        .tabSchedule: T(fr: "Planning", en: "Schedule", pt: "Agenda", it: "Pianificazione", tn: "البلانينغ"),
        .tabGoals: T(fr: "Objectifs", en: "Goals", pt: "Metas", it: "Obiettivi", tn: "الأهداف"),
        .sectionConnection: T(fr: "Connexion", en: "Connection", pt: "Conexão", it: "Connessione", tn: "الاتصال"),
        .apiKey: T(fr: "Clé API Clockify", en: "Clockify API key", pt: "Chave de API do Clockify", it: "Chiave API Clockify", tn: "مفتاح API متاع Clockify"),
        .apiHelp: T(fr: "Profil Clockify → Préférences → Advanced → API. La clé est stockée dans le trousseau macOS.", en: "Clockify profile → Preferences → Advanced → API. The key is stored in the macOS Keychain.", pt: "Perfil do Clockify → Preferences → Advanced → API. A chave fica no Keychain do macOS.", it: "Profilo Clockify → Preferences → Advanced → API. La chiave è nel Portachiavi macOS.", tn: "بروفيل Clockify ← Preferences ← Advanced ← API. المفتاح محفوظ في سلسلة مفاتيح macOS."),
        .connect: T(fr: "Connecter", en: "Connect", pt: "Conectar", it: "Connetti", tn: "اربط"),
        .refreshProjects: T(fr: "Rafraîchir projets", en: "Refresh projects", pt: "Atualizar projetos", it: "Aggiorna progetti", tn: "جدّد المشاريع"),
        .notConnected: T(fr: "Non connecté", en: "Not connected", pt: "Não conectado", it: "Non connesso", tn: "موش مربوط"),
        .useLastProject: T(fr: "Utiliser le dernier projet utilisé", en: "Use last used project", pt: "Usar o último projeto usado", it: "Usa l'ultimo progetto usato", tn: "استعمل آخر مشروع خدمت بيه"),
        .lastUsedFmt: T(fr: "Dernier projet utilisé : %@", en: "Last used project: %@", pt: "Último projeto usado: %@", it: "Ultimo progetto usato: %@", tn: "آخر مشروع: %@"),
        .noneYet: T(fr: "aucun pour l'instant", en: "none yet", pt: "nenhum ainda", it: "nessuno per ora", tn: "ما فماش توّا"),
        .projectsLoadedFmt: T(fr: "%d projet(s) chargé(s).", en: "%d project(s) loaded.", pt: "%d projeto(s) carregado(s).", it: "%d progetto/i caricati.", tn: "%d مشروع محمّل."),
        .sectionDisplay: T(fr: "Affichage", en: "Display", pt: "Exibição", it: "Visualizzazione", tn: "العرض"),
        .showSeconds: T(fr: "Afficher les secondes dans la barre de menu", en: "Show seconds in the menu bar", pt: "Mostrar segundos na barra de menus", it: "Mostra i secondi nella barra dei menu", tn: "ورّي الثواني في شريط القائمة"),
        .launchAtLogin: T(fr: "Lancer au démarrage", en: "Launch at login", pt: "Abrir ao iniciar sessão", it: "Avvia all'accesso", tn: "تقلع وحدها كي يقلع الماك"),
        .sectionHourGoals: T(fr: "Objectifs d'heures", en: "Hour goals", pt: "Metas de horas", it: "Obiettivi orari", tn: "أهداف الساعات"),
        .enableGoals: T(fr: "Activer les objectifs", en: "Enable goals", pt: "Ativar metas", it: "Attiva obiettivi", tn: "فعّل الأهداف"),
        .dailyGoalSettingFmt: T(fr: "Objectif quotidien : %@", en: "Daily goal: %@", pt: "Meta diária: %@", it: "Obiettivo giornaliero: %@", tn: "هدف كل يوم: %@"),
        .weeklyGoalSettingFmt: T(fr: "Objectif hebdo : %@", en: "Weekly goal: %@", pt: "Meta semanal: %@", it: "Obiettivo settimanale: %@", tn: "هدف كل جمعة: %@"),
        .sectionReminders: T(fr: "Rappels", en: "Reminders", pt: "Lembretes", it: "Promemoria", tn: "التذكيرات"),
        .notifyWindowStart: T(fr: "Notifier au début des plages de suivi", en: "Notify at the start of tracking windows", pt: "Notificar no início das janelas de rastreio", it: "Avvisa all'inizio delle fasce", tn: "علّمني في بداية الفترة"),
        .remindersHelp: T(fr: "Nécessite l'app packagée (.app signée) pour les notifications système.", en: "Requires the packaged (signed .app) for system notifications.", pt: "Requer o app empacotado (.app assinado) para notificações.", it: "Richiede l'app pacchettizzata (.app firmata) per le notifiche.", tn: "يلزم التطبيقة packagée (.app موقّعة) باش النوتيفيكاسيونات يخدموا."),
        .sectionLanguage: T(fr: "Langue", en: "Language", pt: "Idioma", it: "Lingua", tn: "اللغة"),

        .trackableWindows: T(fr: "Plages trackables", en: "Trackable windows", pt: "Janelas rastreáveis", it: "Fasce tracciabili", tn: "فترات التراك"),
        .add: T(fr: "Ajouter", en: "Add", pt: "Adicionar", it: "Aggiungi", tn: "زيد"),
        .scheduleHelp: T(fr: "Quand l'auto-suivi est actif, déverrouiller le Mac dans une plage démarre le timer ; le verrouiller (ou sortir de la plage) l'arrête.", en: "When auto-track is on, unlocking the Mac inside a window starts the timer; locking it (or leaving the window) stops it.", pt: "Com o rastreio automático ativo, desbloquear o Mac dentro de uma janela inicia o timer; bloquear (ou sair da janela) o para.", it: "Con il tracciamento automatico attivo, sbloccare il Mac in una fascia avvia il timer; bloccarlo (o uscire dalla fascia) lo ferma.", tn: "كي الأوتو-تراك مفعّل، كي تحلّ الماك في فترة التايمر يبدا؛ وكي تسكّرو (ولا تخرج من الفترة) يوقف."),
        .noWindows: T(fr: "Aucune plage définie.", en: "No window defined.", pt: "Nenhuma janela definida.", it: "Nessuna fascia definita.", tn: "ما فماش فترات."),
        .windowEditorTitle: T(fr: "Plage trackable", en: "Trackable window", pt: "Janela rastreável", it: "Fascia tracciabile", tn: "فترة تراك"),
        .name: T(fr: "Nom", en: "Name", pt: "Nome", it: "Nome", tn: "الاسم"),
        .days: T(fr: "Jours", en: "Days", pt: "Dias", it: "Giorni", tn: "الأيام"),
        .startLabel: T(fr: "Début", en: "Start", pt: "Início", it: "Inizio", tn: "البداية"),
        .endLabel: T(fr: "Fin", en: "End", pt: "Fim", it: "Fine", tn: "النهاية"),
        .cancel: T(fr: "Annuler", en: "Cancel", pt: "Cancelar", it: "Annulla", tn: "بطّل"),
        .defaultWindowName: T(fr: "Nouvelle plage", en: "New window", pt: "Nova janela", it: "Nuova fascia", tn: "فترة جديدة"),

        .wdMon: T(fr: "Lun", en: "Mon", pt: "Seg", it: "Lun", tn: "تنين"),
        .wdTue: T(fr: "Mar", en: "Tue", pt: "Ter", it: "Mar", tn: "ثلاث"),
        .wdWed: T(fr: "Mer", en: "Wed", pt: "Qua", it: "Mer", tn: "اربعا"),
        .wdThu: T(fr: "Jeu", en: "Thu", pt: "Qui", it: "Gio", tn: "خميس"),
        .wdFri: T(fr: "Ven", en: "Fri", pt: "Sex", it: "Ven", tn: "جمعة"),
        .wdSat: T(fr: "Sam", en: "Sat", pt: "Sáb", it: "Sab", tn: "سبت"),
        .wdSun: T(fr: "Dim", en: "Sun", pt: "Dom", it: "Dom", tn: "أحد"),

        .nudgeTitle: T(fr: "Suivi du temps", en: "Time tracking", pt: "Controle de tempo", it: "Monitoraggio tempo", tn: "تسجيل الوقت"),
        .nudgeBodyFmt: T(fr: "La plage « %@ » commence. Démarrer le suivi ?", en: "The window \"%@\" is starting. Start tracking?", pt: "A janela \"%@\" está começando. Iniciar o rastreio?", it: "La fascia \"%@\" sta iniziando. Avviare il tracciamento?", tn: "الفترة « %@ » باش تبدا. نبداو التراك؟"),
    ]
}
