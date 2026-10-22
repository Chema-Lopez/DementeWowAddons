-- TransmogAtlas: localization.
-- Keys are the English texts (used as-is when there is no translation).
-- Only user-facing texts go through L; debug log lines stay in English.
--
-- The language follows the game client by default and can be changed in the options
-- (settings.language = "auto", "enUS" or "esES"). Lookups are resolved on every access, so a
-- change applies as soon as the window is redrawn. Instance, boss and item names come from the
-- game client and always stay in the client's language.

local ADDON, ns = ...

local active -- translation table in use (nil = English)

local L = setmetatable({}, {
    __index = function(_, key)
        return (active and active[key]) or key
    end,
})
ns.L = L

local esES = {
    -- Window
    ["All expansions"] = "Todas las expansiones",
    ["Expansion"] = "Expansión",
    ["Raids"] = "Bandas",
    ["Dungeons"] = "Mazmorras",
    ["Scan"] = "Escanear",
    ["Stop"] = "Parar",
    ["Only missing"] = "Solo lo que falta",
    ["Total"] = "Total",
    ["Class: all"] = "Clase: todas",
    ["Class: mine (%s)"] = "Clase: la mía (%s)",
    ["Class: %s"] = "Clase: %s",
    ["Count pieces for"] = "Contar piezas de",
    ["All classes"] = "Todas las clases",
    ["My class (%s)"] = "Mi clase (%s)",
    ["you have the piece"] = "tienes la pieza",
    ["you have the look from another piece"] = "tienes el aspecto por otra pieza",
    ["missing"] = "te falta",
    ["You have this look from another item, but not this exact piece."] = "Tienes este aspecto por otra pieza, pero no esta pieza en concreto.",
    ["Difficulty"] = "Dificultad",
    ["All difficulties"] = "Todas las dificultades",
    ["Raid Finder"] = "Buscador de bandas",
    ["Normal"] = "Normal",
    ["Heroic"] = "Heroico",
    ["Mythic"] = "Mítico",
    ["Encounter"] = "Jefe",
    ["Loot without encounter"] = "Botín sin jefe",
    ["Loading…"] = "Cargando…",
    ["Loading items… (%d left)"] = "Cargando objetos… (faltan %d)",
    ["Click to see what is missing."] = "Haz clic para ver lo que te falta.",
    ["Nothing to collect here with the current filters."] = "Nada que conseguir aquí con los filtros actuales.",
    ["(not scanned yet)"] = "(sin escanear)",
    ["This instance has no difficulty matching the filter."] = "Esta instancia no tiene ninguna dificultad que encaje con el filtro.",
    ["List truncated: too many items to show."] = "Lista recortada: demasiadas piezas para mostrar.",
    ["Unknown instance."] = "Instancia desconocida.",
    ["No data yet. Press Scan (you can keep playing meanwhile)."] = "Sin datos todavía. Pulsa Escanear (puedes seguir jugando mientras).",
    ["Calculating percentages…"] = "Calculando porcentajes…",
    ["Scanning %d/%s instances"] = "Escaneando %d/%s instancias",
    ["paused: %s"] = "en pausa: %s",
    ["in combat"] = "en combate",
    ["Adventure Guide open"] = "Guía de aventuras abierta",
    ["(new version: press Scan to update the expansion lists, it is quick)"] = "(versión nueva: pulsa Escanear para actualizar las listas de expansiones, es rápido)",
    ["(data from another game version: use /tma rescan)"] = "(datos de otra versión del juego: usa /tma rescan)",
    ["(scan incomplete: press Scan to continue)"] = "(escaneo incompleto: pulsa Escanear para continuar)",
    ["The window could not be created. See /tma errors."] = "No se pudo crear la ventana. Mira /tma errors.",

    -- Scanner
    ["A scan is already running."] = "Ya hay un escaneo en marcha.",
    ["Wait for the current test to finish."] = "Espera a que termine la prueba en curso.",
    ["Wait for the current scan or test to finish."] = "Espera a que termine el escaneo o la prueba en curso.",
    ["Could not load the Adventure Guide."] = "No se pudo cargar la Guía de aventuras.",
    ["Scan finished: %d instances."] = "Escaneo terminado: %d instancias.",
    ["The scan stopped because of an error. Use /tma errors to see it."] = "El escaneo se ha parado por un error. Usa /tma errors para verlo.",
    ["Scanning in the background (%s mode). It pauses in combat or while the Adventure Guide is open."] = "Escaneando en segundo plano (modo %s). Se pausa solo en combate o con la Guía de aventuras abierta.",
    ["normal"] = "normal",
    ["fast"] = "rápido",
    ["Usage: /tma probe <instanceID> [difficulty] (or use it inside an instance)"] = "Uso: /tma probe <idInstancia> [dificultad] (o úsalo dentro de una instancia)",
    ["Usage: /tma verify <instanceID> [difficulty] (or use it inside an instance)"] = "Uso: /tma verify <idInstancia> [dificultad] (o úsalo dentro de una instancia)",
    ["Test finished. Details in /tma log."] = "Prueba terminada. Detalles en /tma log.",
    ["Verification finished. Results in /tma log."] = "Verificación terminada. Resultado en /tma log.",

    -- Commands
    ["open/close the window"] = "abrir/cerrar la ventana",
    ["scan or continue (fast = for when you are AFK)"] = "escanear o continuar (fast = para cuando estés AFK)",
    ["stop the scan"] = "parar el escaneo",
    ["wipe the data and scan from scratch"] = "borrar los datos y escanear de cero",
    ["test one instance with detailed logging (no id: the current one)"] = "probar una instancia con registro detallado (sin id: la actual)",
    ["compare the class filter with Blizzard's"] = "comparar el filtro de clases con el de Blizzard",
    ["show the last n log lines"] = "ver las últimas n líneas del registro",
    ["show stored errors"] = "ver los errores guardados",
    ["show the addon's performance"] = "ver el rendimiento del addon",
    ["toggle debug messages in chat"] = "activar/desactivar mensajes de depuración en el chat",
    ["clear the log"] = "vaciar el registro",
    ["Last %d log lines:"] = "Últimas %d líneas del registro:",
    ["No stored errors."] = "No hay errores guardados.",
    ["The addon profiler is not available."] = "El perfilador de addons no está disponible.",
    ["Stop the scan first with /tma stop."] = "Para antes el escaneo con /tma stop.",
    ["Debug messages in chat: on"] = "Mensajes de depuración en el chat: activados",
    ["Debug messages in chat: off"] = "Mensajes de depuración en el chat: desactivados",
    ["Log cleared."] = "Registro vaciado.",
    ["New version: open /tma and press Scan to update the expansion lists (quick)."] = "Versión nueva: abre /tma y pulsa Escanear para actualizar las listas de expansiones (es rápido).",
    ["There is an unfinished scan. Use /tma scan to continue it."] = "Hay un escaneo a medias. Usa /tma scan para continuarlo.",
    ["turn the summary shown when entering an instance on/off"] = "activar/desactivar el resumen al entrar en una instancia",
    ["turn the chat message for new pieces on/off"] = "activar/desactivar el aviso en el chat al conseguir piezas",
    ["show this character's saved instances"] = "ver las instancias en las que está guardado este personaje",
    ["Instance summary: on"] = "Resumen al entrar en instancias: activado",
    ["Instance summary: off"] = "Resumen al entrar en instancias: desactivado",
    ["New piece messages: on"] = "Avisos de piezas nuevas: activados",
    ["New piece messages: off"] = "Avisos de piezas nuevas: desactivados",
    ["No saved instances for this character."] = "Este personaje no está guardado en ninguna instancia.",
    ["Click to open or close the window."] = "Haz clic para abrir o cerrar la ventana.",

    -- Lockouts
    ["Saved this week: %s"] = "Guardado esta semana: %s",
    ["saved %d/%d · resets in %s"] = "guardado %d/%d · reinicia en %s",
    ["(dead this week)"] = "(muerto esta semana)",
    ["free"] = "libre",
    ["No character data yet."] = "Aún no hay datos de personajes.",
    ["Characters appear here after logging in with the addon."] = "Los personajes aparecen aquí cuando entras con ellos con el addon activado.",

    -- What should I run?
    ["What should I run?"] = "¿Qué me hago hoy?",
    ["Where you can still get the most missing pieces this week (bosses already killed do not count). Uses the class and difficulty filters."] = "Dónde puedes conseguir más piezas que te faltan esta semana (no cuentan los jefes que ya has matado). Usa los filtros de clase y dificultad.",
    ["Calculating…"] = "Calculando…",
    ["Nothing left to get this week with the current filters."] = "No queda nada por conseguir esta semana con los filtros actuales.",
    ["%d to get"] = "%d por conseguir",
    ["(%d of %d bosses left)"] = "(quedan %d de %d jefes)",
    ["…and %d more."] = "…y %d más.",

    -- Search
    ["Search: %s"] = "Búsqueda: %s",
    ["Type at least 2 letters."] = "Escribe al menos 2 letras.",
    ["Searching…"] = "Buscando…",
    ["Instances"] = "Instancias",
    ["Bosses"] = "Jefes",
    ["Pieces"] = "Piezas",
    ["Too many results: type more letters."] = "Demasiados resultados: escribe más letras.",
    ["No results."] = "Sin resultados.",

    -- Instance summary (overlay)
    ["Missing %d of %d pieces (%d%%)"] = "Te faltan %d de %d piezas (%d%%)",
    ["Everything collected here (%d/%d)."] = "Lo tienes todo aquí (%d/%d).",
    ["%d missing"] = "faltan %d",
    ["dead this week"] = "muerto esta semana",
    ["Click to open this instance. Drag to move."] = "Haz clic para abrir esta instancia. Arrastra para moverlo.",
    ["/tma overlay turns this window off."] = "/tma overlay desactiva esta ventana.",

    -- Options
    ["Options"] = "Opciones",
    ["Language"] = "Idioma",
    ["Automatic (game language)"] = "Automático (idioma del juego)",
    ["Summary when entering an instance"] = "Resumen al entrar en una instancia",
    ["Chat message for new pieces"] = "Aviso en el chat de piezas nuevas",
    ["Minimap button"] = "Botón en el minimapa",
    ["show/hide the minimap button"] = "mostrar/ocultar el botón del minimapa",
    ["Search"] = "Buscar",
    ["Language: %s"] = "Idioma: %s",
    ["choose the language: auto, en or es"] = "elegir idioma: auto, en o es",

    -- New piece messages
    ["|cff40ff40New piece|r %s — %s: %s"] = "|cff40ff40Pieza nueva|r %s — %s: %s",
    ["|cff40ff40%d new pieces|r — %s: %s"] = "|cff40ff40%d piezas nuevas|r — %s: %s",
}

local translations = { esES = esES }

-- Languages offered in the options: { code, name shown in its own language }.
ns.LANGUAGES = {
    { code = "enUS", name = "English" },
    { code = "esES", name = "Español" },
}

local function ClientLanguage()
    local locale = GetLocale()
    if locale == "esES" then return "esES" end
    return "enUS"
end

-- lang: "auto" (or nil) to follow the game client, or a code from ns.LANGUAGES.
function ns.SetLanguage(lang)
    if lang == nil or lang == "auto" or not (lang == "enUS" or translations[lang]) then
        lang = ClientLanguage()
    end
    active = translations[lang]
    ns.language = lang
end

ns.SetLanguage("auto")
