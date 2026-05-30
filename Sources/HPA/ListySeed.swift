import Foundation

// First-run seed: the contract activity catalog (sheet "Typy činností ze
// smlouvy") plus two demo months that show both lifecycle states —
// duben 2026 (past: DL primary, OL greyed) and květen 2026 (current: OL only).
enum ListySeed {
    static func catalog() -> [CatalogEntry] {
        var out: [CatalogEntry] = []
        for (cat, items) in raw {
            for it in items { out.append(CatalogEntry(category: cat, item: it)) }
        }
        return out
    }

    static let categories: [String] = raw.map { $0.0 }

    static let raw: [(String, [String])] = [
        ("IT vývoj a IT projekty – tvorba dodavatelských zadání", [
            "Tvorba dodavatelských zadání pro elektronickou třídní knihu (ETK)",
            "Tvorba dodavatelských zadání pro Zónu uchazeče SSGH",
            "Tvorba dodavatelských zadání pro portál praktického vyučování",
            "Tvorba dodavatelských zadání pro DIM (datový informační modul)",
            "Tvorba dodavatelských zadání pro Zónu To dáš!",
            "Tvorba dodavatelských zadání pro aplikaci To natrénuješ",
            "Rozhovory s uživateli a focus groupy",
            "Uživatelská šetření (dotazníky, hloubkové rozhovory, sběr podnětů)",
            "Vyhodnocení uživatelských šetření a návrh roadmapy",
            "Automatizace a nasazení workflow v Asaně / PM nástrojích",
        ]),
        ("IT vývoj a IT projekty – testování", [
            "Testování funkčnosti systémů (manuální testy, bug reporty)",
            "Code review a připomínky k projektům dodavatelů",
            "Návrhy zlepšení práce dodavatelů a kvality výstupů",
            "Nastavení a správa automatických testů",
            "Zajištění beta testingu a školení uživatelů",
            "Monitoring chyb, analýza hlášení a reporting",
        ]),
        ("Analýzy a optimalizace", [
            "Příprava mapy systémů a podkladů pro IT strategii",
            "Zpracování datových analýz z interních systémů (SSGH, To dáš!)",
            "Analýza dat z Google Analytics, BigQuery, Sentry, Clarity",
            "Vyhodnocení trendů užívání systémů a doporučení rozvoje",
            "Doporučení pro interní optimalizaci procesů",
        ]),
        ("Audit a legislativa", [
            "Vytvoření zadání dle podnětů IT auditorů",
            "Vytvoření zadání dle podnětů právních poradců (GDPR, účetnictví, kyberbezpečnost)",
            "Kontrola implementace legislativních změn v systémech",
            "Audit automatizačních procesů a návrhy úprav",
        ]),
        ("Automatizace a procesní nastavení", [
            "Návrh a implementace automatizovaných workflow",
            "Monitoring a optimalizace běžných procesů",
            "Dodání procesních návrhů pro efektivní reporting",
        ]),
        ("Datová migrace", [
            "Tvorba testovacích dat pro migraci",
            "Realizace testů konzistence datové migrace",
            "Zajištění datové migrace mezi systémy",
            "Import nových dat a ověření integrity",
        ]),
        ("Strategické konzultace", [
            "Strategické konzultace dle pokynů objednatele",
            "Prezentace výstupů a doporučení vedení",
            "Návrh priorit a nákladů pro další rozvoj ICT",
        ]),
    ]

    static func months() -> [MonthEntry] {
        var duben = MonthEntry(year: 2026, month: 4)
        duben.dl = MonthDoc(rows: [
            .section("IT vývoj a IT projekty – tvorba dodavatelských zadání"),
            .item("Tvorba dodavatelských zadání pro ETK", 12),
            .item("Tvorba dodavatelských zadání pro Zónu uchazeče", 5),
            .item("Tvorba dodavatelských zadání pro Zónu To dáš", 0),
            .item("Tvorba dodavatelských zadání pro Osobní zónu", 6),
            .item("Rozhovory s uživateli", 3),
            .item("Příprava na IT audit", 5),
            .spacer(),
            .section("IT vývoj a IT projekty – testování"),
            .item("Testování, code review, připomínky zpracovaných projektů", 15),
            .item("Příprava projektu Osobní zóna v2", 20),
            .item("Příprava projektu Portál praktického vyučování", 15),
            .item("Tvorba OSA/SU Hubu", 20),
            .spacer(),
            .item("Stretegické planování 2026", 7, bold: true),
            .item("Otevřené meetingy", 20),
        ])

        var kveten = MonthEntry(year: 2026, month: 5)
        kveten.ol = MonthDoc(rows: [
            .section("IT vývoj a IT projekty – tvorba dodavatelských zadání"),
            .item("Tvorba dodavatelských zadání pro ETK", 10),
            .item("Tvorba dodavatelských zadání pro Zónu uchazeče", 5),
            .item("Tvorba dodavatelských zadání pro Zónu To dáš", 5),
            .item("Tvorba dodavatelských zadání pro Osobní zónu", 10),
            .item("Tvorba dodavatelských zadání pro Interní IT oddělení", 10),
            .item("Rozhovory s uživateli", 6),
            .item("Příprava na IT audit", 10),
            .spacer(),
            .section("IT vývoj a IT projekty – testování"),
            .item("Testování, code review, připomínky zpracovaných projektů", 15),
            .item("Příprava projektu Osobní zóna v2", 15),
            .item("Tvorba OSA/SU Hubu", 15),
            .spacer(),
            .item("Stretegické planování 2026", 7, bold: true),
            .item("Otevřené meetingy", 20),
        ])

        return [duben, kveten]
    }
}
