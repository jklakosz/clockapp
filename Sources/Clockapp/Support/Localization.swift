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

    /// Locale for formatting dates in the chosen language.
    var locale: Locale {
        switch self {
        case .fr: return Locale(identifier: "fr_FR")
        case .en: return Locale(identifier: "en_US")
        case .ptBR: return Locale(identifier: "pt_BR")
        case .it: return Locale(identifier: "it_IT")
        case .tn: return Locale(identifier: "ar_TN")
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
    case smartMerge, mergeTitle, mergeMsgFmt, mergeNothing
    case reviewTitle, reviewIntro, reviewPublish
    // Auto-description
    case tabAutoDesc, autoDescEnable, autoDescHelp, autoDescMappings, autoDescProjectFolders
    case autoDescSessionsRoot, autoDescSessionsHelp, autoDescCommand, autoDescCommandHelp
    case autoDescScheduleEnable, autoDescScheduleAt, autoDescGenerate, autoDescRunningLabel, chooseFolder
    case autoDescGoogleEnable, autoDescGoogleHelp, autoDescGoogleClientId, autoDescGoogleClientSecret
    case autoDescGoogleConnect, autoDescGoogleConnected, autoDescGoogleDisconnect
    case autoDescCalendar, autoDescCalendarSource, autoDescCalOff, autoDescCalAgent, autoDescCalOAuth
    case autoDescCalAgentHelp
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
    // Earnings
    case tabEarnings, sectionEarnings, enableEarnings, hourlyRate, currency
    case sectionUrssaf, urssafDeduct, urssafRate, urssafHelp
    case earnedThisMonth, gross, net, urssafLabel, convertTo, currentRate
    case thisWeek
    // Updates
    case sectionUpdates, currentVersionFmt, checkUpdates, updChecking, updUpToDate
    case receiveRC, receiveRCHelp
    case sectionMCP, mcpEnable, mcpHelp, mcpRunning, mcpStopped, mcpUrlHelp, mcpCopy, mcpCopied
    case updAvailableFmt, updInstall, updInstalling, updFailedFmt
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
        .smartMerge: T(fr: "Fusion intelligente", en: "Smart merge", pt: "Mesclagem inteligente", it: "Unione intelligente", tn: "دمج ذكي"),
        .mergeTitle: T(fr: "Fusionner les entrées ?", en: "Merge entries?", pt: "Mesclar entradas?", it: "Unire le voci?", tn: "تدمج الإدخالات؟"),
        .mergeMsgFmt: T(fr: "%d entrées → %d entrées (%d supprimées sur Clockify)", en: "%d entries → %d entries (%d deleted on Clockify)", pt: "%d entradas → %d entradas (%d excluídas no Clockify)", it: "%d voci → %d voci (%d eliminate su Clockify)", tn: "%d إدخالات → %d إدخالات (%d تتفسخ من Clockify)"),
        .mergeNothing: T(fr: "Rien à fusionner aujourd'hui.", en: "Nothing to merge today.", pt: "Nada para mesclar hoje.", it: "Niente da unire oggi.", tn: "ما فماش شنو تدمج اليوم."),
        .reviewTitle: T(fr: "Vérifier les descriptions", en: "Review descriptions", pt: "Revisar descrições", it: "Rivedi le descrizioni", tn: "راجع الوصوفات"),
        .reviewIntro: T(fr: "Relis et modifie si besoin avant de publier sur Clockify.", en: "Review and edit if needed before publishing to Clockify.", pt: "Revise e edite se necessário antes de publicar no Clockify.", it: "Controlla e modifica se necessario prima di pubblicare su Clockify.", tn: "راجع وبدّل كان يلزم قبل ما تنشر على Clockify."),
        .reviewPublish: T(fr: "Publier", en: "Publish", pt: "Publicar", it: "Pubblica", tn: "أنشر"),
        .tabAutoDesc: T(fr: "Auto-desc", en: "Auto-desc", pt: "Auto-desc", it: "Auto-desc", tn: "Auto-desc"),
        .autoDescEnable: T(fr: "Activer l'auto-description", en: "Enable auto-description", pt: "Ativar auto-descrição", it: "Attiva auto-descrizione", tn: "فعّل الوصف الأوتوماتيكي"),
        .autoDescHelp: T(fr: "Génère les descriptions du jour à partir de tes sessions Claude (via `claude -p`), à relire avant publication.", en: "Generates the day's descriptions from your Claude sessions (via `claude -p`), to review before publishing.", pt: "Gera as descrições do dia a partir das suas sessões Claude (via `claude -p`), para revisar antes de publicar.", it: "Genera le descrizioni del giorno dalle tue sessioni Claude (via `claude -p`), da rivedere prima di pubblicare.", tn: "يولّد الوصوفات متاع اليوم من سيشنات Claude (بـ `claude -p`)، تراجعهم قبل ما تنشر."),
        .autoDescMappings: T(fr: "Projets → dossiers", en: "Projects → folders", pt: "Projetos → pastas", it: "Progetti → cartelle", tn: "المشاريع ← الدوسيات"),
        .autoDescProjectFolders: T(fr: "Associe chaque projet au dossier de ses sessions Claude.", en: "Map each project to the folder of its Claude sessions.", pt: "Associe cada projeto à pasta das suas sessões Claude.", it: "Associa ogni progetto alla cartella delle sue sessioni Claude.", tn: "اربط كل مشروع بالدوسيي متاع سيشناتو."),
        .autoDescSessionsRoot: T(fr: "Racine des sessions Claude", en: "Claude sessions root", pt: "Raiz das sessões Claude", it: "Radice sessioni Claude", tn: "جذر سيشنات Claude"),
        .autoDescSessionsHelp: T(fr: "Dossier contenant les projets Claude (home « trackit »). Vide = ~/.claude/projects.", en: "Folder holding the Claude projects (a \"trackit\" home). Empty = ~/.claude/projects.", pt: "Pasta com os projetos Claude (home \"trackit\"). Vazio = ~/.claude/projects.", it: "Cartella con i progetti Claude (home \"trackit\"). Vuoto = ~/.claude/projects.", tn: "الدوسيي اللي فيه مشاريع Claude (home « trackit »). فارغ = ~/.claude/projects."),
        .autoDescCommand: T(fr: "Commande Claude", en: "Claude command", pt: "Comando Claude", it: "Comando Claude", tn: "أمر Claude"),
        .autoDescCommandHelp: T(fr: "Exécutée avec `-p` (ex. `claude`, ou `CLAUDE_CONFIG_DIR=… claude`).", en: "Run with `-p` (e.g. `claude`, or `CLAUDE_CONFIG_DIR=… claude`).", pt: "Executado com `-p` (ex. `claude`).", it: "Eseguito con `-p` (es. `claude`).", tn: "يتنفّذ بـ `-p` (مثال `claude`)."),
        .autoDescScheduleEnable: T(fr: "Générer automatiquement chaque jour", en: "Generate automatically every day", pt: "Gerar automaticamente todos os dias", it: "Genera automaticamente ogni giorno", tn: "ولّد أوتوماتيك كل نهار"),
        .autoDescScheduleAt: T(fr: "À", en: "At", pt: "Às", it: "Alle", tn: "في"),
        .autoDescGenerate: T(fr: "Auto-description", en: "Auto-describe", pt: "Auto-descrever", it: "Auto-descrivi", tn: "وصف أوتوماتيكي"),
        .autoDescRunningLabel: T(fr: "Génération…", en: "Generating…", pt: "Gerando…", it: "Generazione…", tn: "قاعد يولّد…"),
        .chooseFolder: T(fr: "Choisir…", en: "Choose…", pt: "Escolher…", it: "Scegli…", tn: "اختار…"),
        .autoDescGoogleEnable: T(fr: "Inclure les réunions Google Agenda", en: "Include Google Calendar meetings", pt: "Incluir reuniões do Google Agenda", it: "Includi riunioni Google Calendar", tn: "زيد اجتماعات Google Agenda"),
        .autoDescGoogleHelp: T(fr: "Crée un client OAuth « Desktop » dans Google Cloud (API Calendar activée), puis colle son Client ID et son secret.", en: "Create a \"Desktop\" OAuth client in Google Cloud (Calendar API enabled), then paste its Client ID and secret.", pt: "Crie um cliente OAuth \"Desktop\" no Google Cloud (API Calendar ativada) e cole o Client ID e o segredo.", it: "Crea un client OAuth \"Desktop\" in Google Cloud (API Calendar attiva), poi incolla Client ID e secret.", tn: "اعمل client OAuth « Desktop » في Google Cloud (API Calendar مفعّلة)، وألصق الـ Client ID والـ secret."),
        .autoDescGoogleClientId: T(fr: "Client ID", en: "Client ID", pt: "Client ID", it: "Client ID", tn: "Client ID"),
        .autoDescGoogleClientSecret: T(fr: "Client Secret", en: "Client Secret", pt: "Client Secret", it: "Client Secret", tn: "Client Secret"),
        .autoDescGoogleConnect: T(fr: "Connecter Google", en: "Connect Google", pt: "Conectar Google", it: "Collega Google", tn: "اربط Google"),
        .autoDescGoogleConnected: T(fr: "Google Agenda connecté", en: "Google Calendar connected", pt: "Google Agenda conectado", it: "Google Calendar collegato", tn: "Google Agenda مربوط"),
        .autoDescGoogleDisconnect: T(fr: "Déconnecter", en: "Disconnect", pt: "Desconectar", it: "Scollega", tn: "افصل"),
        .autoDescCalendar: T(fr: "Réunions du jour", en: "Today's meetings", pt: "Reuniões do dia", it: "Riunioni del giorno", tn: "اجتماعات النهار"),
        .autoDescCalendarSource: T(fr: "Source du calendrier", en: "Calendar source", pt: "Fonte do calendário", it: "Fonte calendario", tn: "مصدر الروزنامة"),
        .autoDescCalOff: T(fr: "Désactivé", en: "Off", pt: "Desativado", it: "Disattivato", tn: "مطفي"),
        .autoDescCalAgent: T(fr: "Via l'agent (MCP)", en: "Via the agent (MCP)", pt: "Via agente (MCP)", it: "Tramite l'agente (MCP)", tn: "عبر الوكيل (MCP)"),
        .autoDescCalOAuth: T(fr: "OAuth intégré", en: "Built-in OAuth", pt: "OAuth integrado", it: "OAuth integrato", tn: "OAuth مدمج"),
        .autoDescCalAgentHelp: T(fr: "L'agent Claude récupère lui-même tes réunions via son MCP Google Calendar. Configure un MCP calendrier dans ta config Claude (CLAUDE_CONFIG_DIR) et pré-autorise ses outils. Aucune clé à saisir ici.", en: "The Claude agent fetches your meetings itself via its Google Calendar MCP. Set up a calendar MCP in your Claude config (CLAUDE_CONFIG_DIR) and pre-allow its tools. No keys to enter here.", pt: "O agente Claude busca as reuniões via seu MCP Google Calendar. Configure um MCP de calendário na sua config Claude (CLAUDE_CONFIG_DIR) e pré-autorize as ferramentas. Sem chaves aqui.", it: "L'agente Claude recupera le riunioni tramite il suo MCP Google Calendar. Configura un MCP calendario nella config Claude (CLAUDE_CONFIG_DIR) e pre-autorizza gli strumenti. Nessuna chiave qui.", tn: "الوكيل Claude يجيب الاجتماعات بروحو عبر MCP Google Calendar. عمّر MCP روزنامة في config Claude (CLAUDE_CONFIG_DIR) وسمح لأدواتو. ما فماش مفاتيح هنا."),

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

        .tabEarnings: T(fr: "Rémunération", en: "Earnings", pt: "Ganhos", it: "Compensi", tn: "الفلوس"),
        .sectionEarnings: T(fr: "Revenus estimés", en: "Estimated earnings", pt: "Ganhos estimados", it: "Compensi stimati", tn: "الفلوس المقدّرة"),
        .enableEarnings: T(fr: "Activer le calcul des revenus", en: "Enable earnings calculation", pt: "Ativar cálculo de ganhos", it: "Attiva il calcolo dei compensi", tn: "فعّل حساب الفلوس"),
        .hourlyRate: T(fr: "Taux horaire", en: "Hourly rate", pt: "Valor por hora", it: "Tariffa oraria", tn: "التعريفة في الساعة"),
        .currency: T(fr: "Devise", en: "Currency", pt: "Moeda", it: "Valuta", tn: "العملة"),
        .sectionUrssaf: T(fr: "Cotisations (URSSAF)", en: "Contributions (URSSAF)", pt: "Contribuições (URSSAF)", it: "Contributi (URSSAF)", tn: "المساهمات (URSSAF)"),
        .urssafDeduct: T(fr: "Déduire les cotisations", en: "Deduct contributions", pt: "Deduzir contribuições", it: "Detrai i contributi", tn: "نقّص المساهمات"),
        .urssafRate: T(fr: "Taux de cotisation (%)", en: "Contribution rate (%)", pt: "Taxa de contribuição (%)", it: "Aliquota contributiva (%)", tn: "نسبة المساهمة (%)"),
        .urssafHelp: T(fr: "Micro-entrepreneur BNC : 26,1 % en 2026.", en: "BNC micro-entrepreneur: 26.1% in 2026.", pt: "Micro-empresário BNC: 26,1% em 2026.", it: "Micro-imprenditore BNC: 26,1% nel 2026.", tn: "ميكرو-أونتروبرونور BNC: 26.1% في 2026."),
        .earnedThisMonth: T(fr: "Gagné ce mois", en: "Earned this month", pt: "Ganho este mês", it: "Guadagnato questo mese", tn: "الفلوس هالشهر"),
        .gross: T(fr: "brut", en: "gross", pt: "bruto", it: "lordo", tn: "خام"),
        .net: T(fr: "net", en: "net", pt: "líquido", it: "netto", tn: "صافي"),
        .urssafLabel: T(fr: "URSSAF", en: "URSSAF", pt: "URSSAF", it: "URSSAF", tn: "URSSAF"),
        .convertTo: T(fr: "Convertir vers", en: "Convert to", pt: "Converter para", it: "Converti in", tn: "حوّل لـ"),
        .currentRate: T(fr: "Taux actuel", en: "Current rate", pt: "Taxa atual", it: "Tasso attuale", tn: "التصريف الحالي"),
        .thisWeek: T(fr: "Cette semaine", en: "This week", pt: "Esta semana", it: "Questa settimana", tn: "هالجمعة"),

        .receiveRC: T(fr: "Recevoir les versions candidates (RC)", en: "Receive release candidates (RC)", pt: "Receber versões candidatas (RC)", it: "Ricevi release candidate (RC)", tn: "أستقبل النسخ التجريبية (RC)"),
        .receiveRCHelp: T(fr: "Propose aussi les pré-versions, avant leur sortie stable.", en: "Also offers pre-releases, before their stable release.", pt: "Também oferece pré-lançamentos, antes da versão estável.", it: "Propone anche le pre-release, prima della versione stabile.", tn: "يقترح زادة النسخ قبل ما تخرج الرسمية."),

        .sectionMCP: T(fr: "Serveur MCP", en: "MCP server", pt: "Servidor MCP", it: "Server MCP", tn: "سيرفار MCP"),
        .mcpEnable: T(fr: "Activer le serveur MCP", en: "Enable MCP server", pt: "Ativar servidor MCP", it: "Attiva server MCP", tn: "فعّل سيرفار MCP"),
        .mcpHelp: T(fr: "Permet à un assistant (Claude…) de lire/éditer l'entrée en cours. Nécessite Node.js installé.", en: "Lets an assistant (Claude…) read/edit the running entry. Requires Node.js installed.", pt: "Permite que um assistente (Claude…) leia/edite a entrada em curso. Requer Node.js instalado.", it: "Consente a un assistente (Claude…) di leggere/modificare la voce in corso. Richiede Node.js.", tn: "يخلّي مساعد (Claude…) يقرا/يبدّل الإدخال الجاري. يلزم Node.js مركّب."),
        .mcpRunning: T(fr: "En cours d'exécution", en: "Running", pt: "Em execução", it: "In esecuzione", tn: "خدّام"),
        .mcpStopped: T(fr: "Arrêté", en: "Stopped", pt: "Parado", it: "Fermo", tn: "واقف"),
        .mcpUrlHelp: T(fr: "Ajoute cette URL à ton client MCP :", en: "Add this URL to your MCP client:", pt: "Adicione este URL ao seu cliente MCP:", it: "Aggiungi questo URL al tuo client MCP:", tn: "زيد هالURL في client MCP متاعك:"),
        .mcpCopy: T(fr: "Copier", en: "Copy", pt: "Copiar", it: "Copia", tn: "أنسخ"),
        .mcpCopied: T(fr: "Copié !", en: "Copied!", pt: "Copiado!", it: "Copiato!", tn: "تنسخ!"),

        .sectionUpdates: T(fr: "Mises à jour", en: "Updates", pt: "Atualizações", it: "Aggiornamenti", tn: "التحديثات"),
        .currentVersionFmt: T(fr: "Version actuelle : %@", en: "Current version: %@", pt: "Versão atual: %@", it: "Versione attuale: %@", tn: "النسخة الحالية: %@"),
        .checkUpdates: T(fr: "Vérifier les mises à jour", en: "Check for updates", pt: "Verificar atualizações", it: "Controlla aggiornamenti", tn: "شوف كان فما تحديث"),
        .updChecking: T(fr: "Vérification…", en: "Checking…", pt: "Verificando…", it: "Controllo…", tn: "قاعد يشوف…"),
        .updUpToDate: T(fr: "À jour.", en: "Up to date.", pt: "Atualizado.", it: "Aggiornato.", tn: "آخر نسخة عندك."),
        .updAvailableFmt: T(fr: "Version %@ disponible", en: "Version %@ available", pt: "Versão %@ disponível", it: "Versione %@ disponibile", tn: "النسخة %@ موجودة"),
        .updInstall: T(fr: "Installer et relancer", en: "Install and relaunch", pt: "Instalar e reiniciar", it: "Installa e riavvia", tn: "ركّبها وأعاود شغّل"),
        .updInstalling: T(fr: "Installation…", en: "Installing…", pt: "Instalando…", it: "Installazione…", tn: "قاعد يركّب…"),
        .updFailedFmt: T(fr: "Échec : %@", en: "Failed: %@", pt: "Falhou: %@", it: "Errore: %@", tn: "ما مشاتش: %@"),

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
