--[[
	Lang.lua
	Textes vus par le joueur. Le code les écrit en anglais : ce texte sert de
	clé, la traduction française est dans le dictionnaire ci-dessous.
	  - Lang.T(texte) : texte traduit ;
	  - Lang.F(modèle, ...) : modèle traduit puis rempli (string.format) ; une
	    traduction garde les mêmes %s / %d, dans le même ordre ;
	  - Lang.Plural(n, singulier, pluriel) : mot traduit, au singulier ou au
	    pluriel (en français, 0 et 1 restent au singulier).
	Langue : Config.Language ("fr" ou "en"), la même pour le serveur et tous
	les clients : un message formé par le serveur arrive déjà traduit.
	Un texte sans traduction reste en anglais et est noté dans Lang.Missing
	(tools/sim/test_langue.luau vérifie qu'il n'y en a aucun à l'écran).
	string.upper ne connaît pas les accents : les clés en majuscules ont une
	traduction déjà en majuscules.
	Pour les tests, shared.HoH_Language impose une langue (le simulateur joue
	les anciens scénarios en anglais).
]]

local Config = require(script.Parent.Config)

local Lang = {}

-- Textes notés sans traduction (français seulement)
Lang.Missing = {} :: { [string]: boolean }

local FR: { [string]: string } = {
	-- Équipes
	["FOX"] = "RENARD",
	["FOXES"] = "RENARDS",
	["a FOX"] = "un RENARD",
	["CHICKEN"] = "POULE",
	["CHICKENS"] = "POULES",
	["a CHICKEN"] = "une POULE",
	["SNAKE"] = "VIPÈRE",
	["SNAKES"] = "VIPÈRES",
	["a SNAKE"] = "une VIPÈRE",
	["Catch your prey. Run from your hunter."] = "Attrape ta proie. Fuis ton chasseur.",
	["You are %s - Catch %s - Avoid %s"] = "Tu es %s - Attrape les %s - Fuis les %s",

	-- Modes
	["CHASE"] = "POURSUITE",
	["Catch your prey, dodge your hunter. Last team standing wins!"] = "Attrape ta proie, fuis ton chasseur. Derniers debout gagnent !",
	["Catch your prey, dodge your hunter."] = "Attrape ta proie, esquive ton chasseur.",
	["Carry downed teammates home."] = "Porte tes coéquipiers à terre jusqu'au camp.",
	["Last team standing wins."] = "La dernière équipe debout gagne.",
	["EGG RUN"] = "COURSE AUX ŒUFS",
	["Grab painted eggs and run them home. First to 5 wins!"] = "Rapporte 5 œufs peints dans ton camp pour gagner !",
	["Grab a painted egg from a nest."] = "Prends un œuf peint dans un nid.",
	["Run it into your camp. Carriers can't catch."] = "Rapporte-le dans ton camp. Le porteur ne peut pas attraper.",
	["First team to 5 eggs wins."] = "La première équipe à 5 œufs gagne.",
	["CAROUSEL"] = "MANÈGE",
	["Ride the flying horses: outnumber the others under them to score!"] = "Sois plus nombreux sous les chevaux volants pour marquer !",
	["Three flying horses circle the valley."] = "Trois chevaux volants tournent au-dessus de la vallée.",
	["Outnumber others in a horse's ring."] = "Sois plus nombreux que les autres dans l'anneau d'un cheval.",
	["First team to 120 points wins."] = "La première équipe à 120 points gagne.",
	["GOLDEN EGG"] = "ŒUF D'OR",
	["Bring the golden egg home. First team to 3 wins!"] = "Rapporte l'œuf d'or au camp. La première équipe à 3 gagne !",
	["One golden egg spawns in the middle."] = "Un œuf d'or apparaît au centre.",
	["Carry it to your camp to score."] = "Porte-le dans ton camp pour marquer.",
	["First team to 3 eggs wins."] = "La première équipe à 3 œufs gagne.",
	["RAID"] = "RAID",
	["Steal eggs from your prey's base. Most eggs wins!"] = "Vole les œufs du camp de ta proie. Le plus d'œufs gagne !",
	["Each camp keeps a pile of eggs."] = "Chaque camp garde un tas d'œufs.",
	["Steal from your prey's camp, bring it home."] = "Vole dans le camp de ta proie, rapporte au tien.",
	["Most eggs when time runs out wins."] = "Le plus d'œufs à la fin du temps gagne.",
	["THE PACK"] = "LA MEUTE",
	["Pure conversion. Last team standing wins!"] = "Conversion pure. La dernière équipe debout gagne !",
	["No objective: only the chase."] = "Pas d'objectif : rien que la poursuite.",
	["Caught players fall: carry teammates home."] = "Les joueurs attrapés tombent : porte tes coéquipiers au camp.",
	["Last team standing wins (or biggest team)."] = "La dernière équipe debout gagne (ou la plus nombreuse).",

	-- Cartes
	["The Farm"] = "La Ferme",
	["Golden Egg"] = "Œuf d'or",
	["Carousel Valley"] = "Vallée du Manège",
	["Carousel"] = "Manège",
	["The Canyon"] = "Le Canyon",
	["Raid"] = "Raid",
	["The Swamp"] = "Le Marais",
	["The Pack"] = "La Meute",
	["SAFE ZONE"] = "ZONE SÛRE",
	["%s CAMP"] = "CAMP %s",
	["BIG RED BARN"] = "GRANDE GRANGE ROUGE",
	["RED ROCK"] = "ROCHER ROUGE",

	-- HUD
	["LOBBY"] = "LOBBY",
	["READY"] = "PRÊTS",
	["ROUND"] = "MANCHE",
	["END"] = "FIN",
	["Objective completed"] = "Objectif atteint",
	["Last team standing"] = "Dernière équipe debout",
	["Time's up"] = "Temps écoulé",
	["No winner this time"] = "Pas de gagnant cette fois",
	["ROUND STAR"] = "STAR DE LA MANCHE",
	["LONGEST RUN"] = "MEILLEUR SURVIVANT",
	["TOP CATCHER"] = "MEILLEUR CHASSEUR",
	["SHOP"] = "BOUTIQUE",
	["SPIN"] = "ROUE",
	["HELP"] = "AIDE",
	["COINS"] = "PIÈCES",
	["COINS  [2X]"] = "PIÈCES  [x2]",
	["VOTE FOR THE NEXT MODE"] = "VOTE POUR LE PROCHAIN MODE",
	["A round is in progress. You'll join the next one!"] = "Une manche est en cours. Tu joueras à la suivante !",
	["%s (you)"] = "%s (toi)",
	["+%d more"] = "+%d autres",
	["HOW TO PLAY"] = "COMMENT JOUER",
	["Catch your prey. Run from your hunter.\nFOX catches CHICKEN, CHICKEN catches SNAKE, SNAKE catches FOX.\nOutlines show teams: FOX orange, CHICKEN yellow, SNAKE green.\nCaught? You're down. A teammate can carry you to your base to revive you.\n"] = "Attrape ta proie. Fuis ton chasseur.\nLe RENARD attrape la POULE, la POULE attrape la VIPÈRE, la VIPÈRE attrape le RENARD.\nLe contour montre l'équipe : RENARDS orange, POULES jaunes, VIPÈRES vertes.\nAttrapé ? Tu es à terre. Un coéquipier peut te porter jusqu'à ton camp pour te relever.\n",
	["No rescue in %ds? You join the team that caught you.\nNobody can catch you in your base's SAFE ZONE.\n\n"] = "Personne en %d s ? Tu rejoins l'équipe qui t'a attrapé.\nDans la ZONE SÛRE de ton camp, personne ne peut t'attraper.\n\n",
	["Q / E : dash sideways    F : stop dead    R : your animal's ability\nC : carry a downed teammate home    Hide in tall grass and bushes!"] = "Q / E : esquive sur le côté    F : arrêt net    R : pouvoir de ton animal\nC : porter un coéquipier à terre jusqu'au camp    Cache-toi dans les hautes herbes et les buissons !",
	["DASH buttons : dodge sideways    STOP : stop dead    Big button : ability\nCARRY : pick up a downed teammate    Hide in tall grass!"] = "Boutons ESQUIVE : sur le côté    STOP : arrêt net    Gros bouton : pouvoir\nPORTER : ramasser un coéquipier à terre    Cache-toi dans les hautes herbes !",
	["Next round soon"] = "Prochaine manche bientôt",
	["%s: %s"] = "%s : %s",
	["LV %d"] = "NIV %d",
	["LEVEL %d"] = "NIVEAU %d",
	["on %s"] = "sur %s",
	["vote"] = "vote",
	["votes"] = "votes",
	["player"] = "joueur",
	["players"] = "joueurs",
	["everyone voted · ties: the mode played least recently"] = "tout le monde a voté · égalité : le mode le moins joué récemment",
	["waiting for: %s"] = "on attend : %s",
	["%s WIN!"] = "VICTOIRE DES %s !",
	["DRAW!"] = "ÉGALITÉ !",
	["Your team won! "] = "Ton équipe a gagné ! ",
	["Your team lost. "] = "Ton équipe a perdu. ",
	["+%d coins   (%s)"] = "+%d pièces   (%s)",
	["Catches"] = "Captures",
	["Objectives"] = "Objectifs",
	["Played"] = "Participation",
	["Survival"] = "Survie",
	["Victory"] = "Victoire",
	["LEVEL UP! Level %d"] = "NIVEAU SUPÉRIEUR ! Niveau %d",
	["You: %d %s  ·  %ds longest survival"] = "Toi : %d %s  ·  %d s de survie au plus long",
	["catch"] = "capture",
	["catches"] = "captures",
	["objective"] = "objectif",
	["objectives"] = "objectifs",
	["Vote for the next mode!"] = "Vote pour le prochain mode !",
	["Waiting for players..."] = "En attente de joueurs...",
	["Back to the lobby soon"] = "Retour au lobby bientôt",
	["Walk onto a plate or tap a card · one vote each"] = "Marche sur une plaque ou touche une carte · un vote chacun",
	["first to %d %s"] = "premiers à %d %s",
	["points"] = "points",
	["eggs"] = "œufs",
	["last team standing"] = "dernière équipe debout",
	['<font color="%s">%s</font>  ·  catch <font color="%s">%s</font>  ·  avoid <font color="%s">%s</font>'] = '<font color="%s">%s</font>  ·  attrape les <font color="%s">%s</font>  ·  fuis les <font color="%s">%s</font>',
	["Level %d: +%d coins"] = "Niveau %d : +%d pièces",
	["Unlocked %s (free)"] = "Débloqué : %s (offert)",

	-- Boutons d'action
	["DASH"] = "ESQUIVE",
	["STOP"] = "STOP",
	["ABILITY"] = "POUVOIR",
	["CARRY"] = "PORTER",
	["DROP"] = "LÂCHER",
	["SPRINT"] = "SPRINT",
	["GLIDE JUMP"] = "VOL PLANÉ",
	["BITE"] = "MORSURE",

	-- Fil des captures, étiquettes, effets
	["saved"] = "a sauvé",
	["joined the"] = "rejoint les",
	["DOWN"] = "À TERRE",
	["SAFE"] = "À L'ABRI",
	["PREY"] = "PROIE",
	["HUNTER"] = "CHASSEUR",
	["DOWN!"] = "À TERRE !",
	["%s DOWN!"] = "%s À TERRE !",
	["SAVED!"] = "DEBOUT !",
	["SLOWED"] = "RALENTI",
	["%s SCORE!"] = "LES %s MARQUENT !",

	-- Secours
	["Tap CARRY to save %s"] = "Touche PORTER pour sauver %s",
	["Press %s to carry %s"] = "Appuie sur %s pour porter %s",
	["HELP!"] = "SOS",
	["CARRIED HOME by %s · hold on!"] = "PORTÉ AU CAMP par %s · tiens bon !",
	["YOU'RE DOWN · %ds · a teammate can carry you home"] = "À TERRE · %d s · un coéquipier peut te porter au camp",
	["CARRYING %s · run to your base!"] = "TU PORTES %s · cours jusqu'à ton camp !",
	["SAFE ZONE · nobody can catch you here"] = "ZONE SÛRE · personne ne peut t'attraper ici",
	["%s is down · %dm · carry them home"] = "%s est à terre · %d m · à porter au camp",
	["You caught %s!"] = "Tu as attrapé %s !",
	["%s caught you! A teammate can carry you home."] = "%s t'a attrapé ! Un coéquipier peut te porter au camp.",
	["%s is carrying you home!"] = "%s te porte au camp !",
	["%s saved you! Back in the game!"] = "%s t'a sauvé ! De retour en jeu !",
	["You saved %s!"] = "Tu as sauvé %s !",
	["You're safe at your base. Back in the game!"] = "Tu es à l'abri dans ton camp. De retour en jeu !",
	["Nobody carried you home in time."] = "Personne ne t'a porté au camp à temps.",
	["No teammate left to carry you."] = "Plus aucun coéquipier pour te porter.",
	["You left the ground."] = "Tu as réapparu.",
	["Now catch %s!"] = "Attrape maintenant les %s !",
	["You're %s now."] = "Tu es maintenant %s.",
	["%s caught you! You're %s."] = "%s t'a attrapé ! Tu es maintenant %s.",
	["Bitten! You are slowed!"] = "Mordu ! Tu es ralenti !",

	-- Manche
	["Next round in"] = "Prochaine manche dans",
	["Leading: %s"] = "En tête : %s",
	["Vote for a mode!"] = "Votez pour un mode !",
	["Round starting"] = "La manche commence",
	["Round in progress"] = "Manche en cours",
	["Next: %s on %s"] = "Prochain : %s sur %s",
	["You are %s!"] = "Tu es %s !",
	["You joined as %s!"] = "Tu rejoins la manche : tu es %s !",
	["GO!"] = "PARTEZ !",
	["%s converted everyone!"] = "Les %s ont converti tout le monde !",
	["%s reached the goal: %d %s"] = "Les %s ont atteint l'objectif : %d %s",
	["Nobody left in the round"] = "Plus personne dans la manche",
	["Time's up: %s had the most %s (%d)"] = "Temps écoulé : les %s ont le plus de %s (%d)",
	["Time's up: %s were the biggest team (%d)"] = "Temps écoulé : les %s sont les plus nombreux (%d)",
	["Time's up: teams were tied in size, %s had the best score (%d)"] = "Temps écoulé : équipes de même taille, les %s ont le meilleur score (%d)",
	["Time's up with equal teams: no winner"] = "Temps écoulé, équipes égales : pas de gagnant",
	["%d pts"] = "%d pts",
	["%.1fs"] = "%.1f s",
	["It's a draw!"] = "Égalité !",
	["Round error, returning to lobby"] = "Erreur de manche, retour au lobby",

	-- Modes en jeu
	["An egg was dropped!"] = "Un œuf est tombé !",
	["An egg fell!"] = "Un œuf a roulé !",
	["You have an egg! Run it to your camp!"] = "Tu as un œuf ! Cours le poser dans ton camp !",
	["%s scored an egg! (%d/%d)"] = "Les %s marquent un œuf ! (%d/%d)",
	["%s: %d points!"] = "%s : %d points !",
	["The carousel turns the other way!"] = "Le manège change de sens !",
	["The egg was dropped!"] = "L'œuf est tombé !",
	["Egg knocked loose!"] = "L'œuf a roulé !",
	["%s have the egg!"] = "Les %s ont l'œuf !",
	["%s scored! (%d/%d)"] = "Les %s marquent ! (%d/%d)",
	["A new golden egg appeared!"] = "Un nouvel œuf d'or est apparu !",
	["%s stole an egg from the %s!"] = "Les %s volent un œuf aux %s !",
	["%s now have %d eggs!"] = "Les %s ont maintenant %d œufs !",
	["The egg went back to the %s!"] = "L'œuf retourne chez les %s !",
	["Flying to the %s camp!"] = "En route vers le camp %s !",

	-- Lobby
	["HUNT OR HIDE"] = "POULE, POULE, RENARD, VIPÈRE",
	["TOP WINS"] = "VICTOIRES",
	["TOP CATCHES"] = "CAPTURES",
	["ALL TIME"] = "DE TOUS LES TEMPS",
	["Loading..."] = "Chargement...",
	["DAILY SPIN"] = "ROUE DU JOUR",
	["Spin"] = "Tourner",
	["Daily Spin"] = "Roue du jour",
	["Open Shop"] = "Ouvrir la boutique",
	["Shop"] = "Boutique",
	["WHO CATCHES WHO?"] = "QUI ATTRAPE QUI ?",
	["DASH PRACTICE"] = "ENTRAÎNEMENT À L'ESQUIVE",
	["Play a round to\nappear here!"] = "Joue une manche\npour apparaître ici !",
	["Player %d"] = "Joueur %d",
	["Leaderboards need\nAPI access enabled"] = "Classements : activer\nl'accès aux API",

	-- Roue du jour
	["25 coins"] = "25 pièces",
	["60 XP"] = "60 XP",
	["75 coins"] = "75 pièces",
	["150 coins"] = "150 pièces",
	["150 XP"] = "150 XP",
	["500 coins"] = "500 pièces",
	["%dh %02dm"] = "%d h %02d",
	["%dm"] = "%d min",
	["Next free spin in %s"] = "Prochain tour gratuit dans %s",
	["%s (owned: +%d coins)"] = "%s (déjà à toi : +%d pièces)",
	["Daily Spin: you won %s!"] = "Roue du jour : tu gagnes %s !",

	-- Boutique
	["A hat on top of your avatar. Cosmetic only."] = "Un chapeau sur ton avatar. Simple décoration.",
	["A trail behind you when you run. Cosmetic only."] = "Une traînée derrière toi quand tu cours. Simple décoration.",
	["Plays when you catch someone. Cosmetic only."] = "Se joue quand tu attrapes quelqu'un. Simple décoration.",
	["%d coins"] = "%d pièces",
	["EQUIPPED"] = "ÉQUIPÉ",
	["EQUIP"] = "ÉQUIPER",
	["Owned"] = "Possédé",
	["Need %d more"] = "Il manque %d",
	["GET"] = "OBTENIR",
	["Coin pack"] = "Pack de pièces",
	["BUY"] = "ACHETER",
	["HATS"] = "CHAPEAUX",
	["TRAILS"] = "TRAÎNÉES",
	["CATCH FX"] = "EFFETS",
	["PASSES"] = "PASS",
	["No Hat"] = "Sans chapeau",
	["Crown"] = "Couronne",
	["Top Hat"] = "Haut-de-forme",
	["Party Hat"] = "Chapeau de fête",
	["Halo"] = "Auréole",
	["No Trail"] = "Sans traînée",
	["Sparkle Trail"] = "Traînée scintillante",
	["Fire Trail"] = "Traînée de feu",
	["Rainbow Trail"] = "Traînée arc-en-ciel",
	["Classic Pop"] = "Pop classique",
	["Confetti"] = "Confettis",
	["Star Burst"] = "Pluie d'étoiles",
	["Hearts"] = "Cœurs",
	["Lightning"] = "Éclair",
	["VIP"] = "VIP",
	["x2 coins every round (cosmetics only)"] = "x2 pièces à chaque manche (cosmétiques seulement)",
	["Your profile is still loading."] = "Ton profil est en cours de chargement.",
	["You already own %s."] = "Tu as déjà %s.",
	["Not enough coins! %s costs %d."] = "Pas assez de pièces ! %s coûte %d.",
	["Unlocked %s!"] = "Débloqué : %s !",
	["Thanks for your purchase!"] = "Merci pour ton achat !",
	["Your data couldn't be loaded. Progress won't be saved this session."] = "Tes données n'ont pas pu être chargées. Ta progression ne sera pas sauvegardée cette fois.",
}

function Lang.Code(): string
	local forced = shared.HoH_Language
	if forced == "en" or forced == "fr" then
		return forced
	end
	return if Config.Language == "en" then "en" else "fr"
end

function Lang.T(text: string): string
	if Lang.Code() ~= "fr" then
		return text
	end
	local translated = FR[text]
	if translated == nil then
		Lang.Missing[text] = true
		return text
	end
	return translated
end

function Lang.F(pattern: string, ...: any): string
	return string.format(Lang.T(pattern), ...)
end

function Lang.Plural(count: number, singular: string, plural: string): string
	local one = if Lang.Code() == "fr" then math.abs(count) < 2 else count == 1
	return Lang.T(if one then singular else plural)
end

-- Pour les tests : toutes les clés du dictionnaire français
function Lang.FrenchKeys(): { [string]: string }
	return FR
end

return Lang
