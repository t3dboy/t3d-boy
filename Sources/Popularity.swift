// T3d Boy — "Most popular by reviews" ranking.
//
// Baked-in table (0-100) curated from critic-review consensus
// (GameRankings/Metacritic era) seeded with Wikipedia's best-selling
// Game Boy games list. Baked at build time deliberately: live review APIs
// need per-user API keys and ~1350 rate-limited lookups per library scan.
// Unscored ROMs sort below scored ones, alphabetically.

import Foundation

enum Popularity {
    // Lowercase; "&" → "and"; ", the"/leading "the" dropped; alphanumerics only
    static func normalize(_ name: String) -> String {
        var s = name.lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: ", the", with: "")
        if s.hasPrefix("the ") { s = String(s.dropFirst(4)) }
        return s.filter { $0.isLetter || $0.isNumber }
    }

    static func score(for url: URL) -> Int? {
        var name = url.deletingPathExtension().lastPathComponent
        name = name.replacingOccurrences(
            of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        return scores[normalize(name)]
    }

    private static let scores: [String: Int] = [
        // Nintendo flagships
        "tetris": 92, "tetrisdx": 88, "drmario": 80,
        "supermarioland": 79, "supermarioland26goldencoins": 84,
        "wariolandsupermarioland3": 83, "warioland2": 85, "warioland3": 87,
        "supermariobrosdeluxe": 92, "donkeykong": 92,
        "donkeykongland": 74, "donkeykongland2": 73, "donkeykongland3": 72,
        "donkeykongcountry": 79,
        "legendofzeldalinksawakening": 90, "legendofzeldalinksawakeningdx": 91,
        "legendofzeldaoracleofages": 91, "legendofzeldaoracleofseasons": 91,
        "metroid2returnofsamus": 79, "metroidiireturnofsamus": 79,
        "kirbysdreamland": 78, "kirbysdreamland2": 80, "kirbyspinballland": 76,
        "kirbysstarstacker": 75, "kirbytiltntumble": 79,
        "mariotennis": 91, "mariogolf": 90, "mariospicross": 80,
        "yoshi": 70, "yoshiscookie": 75, "alleyway": 65,
        "golf": 70, "tennis": 70, "baseball": 60, "f1race": 68,
        "balloonkid": 78, "kidicarusofmythsandmonsters": 75,
        "molemania": 81, "waverace": 75, "qix": 72,
        "gameandwatchgallery": 75, "gameandwatchgallery2": 78, "gameandwatchgallery3": 80,

        // Pokémon
        "pokemonredversion": 88, "pokemonblueversion": 88, "pokemonred": 88, "pokemonblue": 88,
        "pokemonyellowversionspecialpikachuedition": 85, "pokemonyellowversion": 85, "pokemonyellow": 85,
        "pokemongoldversion": 91, "pokemonsilverversion": 91, "pokemongold": 91, "pokemonsilver": 91,
        "pokemoncrystalversion": 87, "pokemoncrystal": 87,
        "pokemonpinball": 81, "pokemontradingcardgame": 82, "pokemonpuzzlechallenge": 86,

        // Third-party standouts
        "metalgearsolid": 90, "shantae": 82,
        "gargoylesquest": 80, "finalfantasyadventure": 82,
        "finalfantasylegend": 76, "finalfantasylegend2": 80, "finalfantasylegend3": 78,
        "swordofhopeii": 72,
        "megamanv": 84, "megaman5": 84, "megamandrwilysrevenge": 75,
        "megaman2": 72, "megaman3": 74, "megaman4": 76,
        "bioniccommando": 84, "bioniccommandoeliteforces": 78,
        "castlevania2belmontsrevenge": 80, "castlevaniaiibelmontsrevenge": 80,
        "castlevaniaadventure": 60, "castlevanialegends": 65, "kiddracula": 78,
        "operationc": 80, "nemesis": 76, "gradiusinterstellarassault": 78,
        "rtype": 78, "rtype2": 75, "rtypedx": 85,
        "ninjagaidenshadow": 78, "doubledragon": 75,
        "teenagemutantninjaturtlesfallofthefootclan": 75,
        "batmanvideogame": 72, "batmanreturnofthejoker": 75,
        "ducktales": 80, "ducktales2": 78, "darkwingduck": 74,
        "adventureisland": 73, "adventureisland2aliensinparadise": 76,
        "bubblebobble": 72, "burgertimedeluxe": 78, "boxxle": 72,
        "catrap": 78, "daedalianopus": 75, "avengingspirit": 80, "tripworld": 76,
        "pacman": 70, "mspacman": 73, "galagaandgalaxian": 74,
        "spaceinvaders": 68, "lemmings": 70, "pipedream": 70,
        "primalrage": 55, "mortalkombat": 58, "streetfighter2": 65,
        "fortifiedzone": 73, "solarstriker": 70, "trax": 74,
        "buraifighterdeluxe": 77, "mercenaryforce": 70,
        "princeofpersia": 75, "earthwormjim": 65,

        // RPGs / adventure on GB+GBC
        "dragonwarrior3": 85, "dragonwarrioriii": 85,
        "dragonwarrior1and2": 80, "dragonwarrioriandii": 80,
        "dragonwarriormonsters": 80, "dragonwarriormonsters2covestarstale": 75,
        "dragonwarriormonsters2tarasadventure": 75,
        "harvestmoongb": 75, "harvestmoon2gbc": 73, "harvestmoon3gbc": 72,
        "survivalkids": 77, "azuredreams": 72, "crystalis": 70,
        "lufialegendreturns": 72, "maginationkeepersofthestone": 80, "magination": 80,
        "legendofriverking": 70, "legendofriverking2": 68,
        "revelationsdemonslayer": 65, "wizardryempire": 65,

        // GBC era highlights
        "tobytori": 84, "tokitori": 84, "mrdriller": 76,
        "raymangbc": 78, "rayman": 78, "tombraider": 80,
        "tombraidercurseofthesword": 74, "toystoryracer": 75,
        "wackyraces": 78, "conkerspockettales": 65,
        "blastermasterenemybelow": 78, "wendyeverywitchway": 80,
        "aladdin": 76, "tarzan": 70, "wormsarmageddon": 72,
        "residentevilgaiden": 60, "grandtheftauto": 60, "grandtheftauto2": 58,
        "tonyhawksproskater2": 80, "tonyhawksproskater3": 72,
        "santaclausejr": 55, "spiderman": 68,
        "yugiohdarkduelstories": 65, "yugiohduelmonsters": 60,
    ]
}
