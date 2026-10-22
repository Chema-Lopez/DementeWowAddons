-- MountAtlas: localization.
-- Keys are the English texts (used as-is when there is no translation).
-- The language follows the game client: English, or Spanish on esES clients.
-- Mount names come from the game client; Simple Armory's subcategory names are translated
-- here when they are generic ("Raid Drop", "Vendor"...) and kept in English when they are
-- proper names ("Argent Tournament", "Remix: Legion"...).

local ADDON, ns = ...

local esES = {
    -- Window
    ["All"] = "Todo",
    ["Search"] = "Buscar",
    ["Only missing"] = "Solo lo que falta",
    ["Options"] = "Opciones",
    ["Total"] = "Total",
    ["Sources: all"] = "Orígenes: todos",
    ["Sources: %d of %d"] = "Orígenes: %d de %d",
    ["Availability"] = "Disponibilidad",
    ["Select all"] = "Marcar todo",
    ["Select none"] = "Desmarcar todo",
    ["Source"] = "Origen",
    ["Nothing to show with the current filters."] = "No hay nada que mostrar con los filtros actuales.",
    ["No results."] = "Sin resultados.",
    ["Search: %s"] = "Búsqueda: %s",
    ["Show the other faction's mounts"] = "Mostrar monturas de la otra facción",
    ["Hide mounts now only sold on the Black Market"] = "Ocultar las que ya solo se venden en la Subasta Negra",
    ["Old promotion mounts (BlizzCon, collector's editions…) that can now only be bought, for a lot of gold, on the Black Market Auction House. Hidden and not counted unless you have them."] = "Monturas de promociones antiguas (BlizzCon, ediciones de coleccionista…) que hoy solo se pueden comprar, por mucho oro, en la Casa de Subastas Negra. Se ocultan y no cuentan en el % salvo que ya las tengas.",
    ["Mount data: Simple Armory (%s)"] = "Datos de monturas: Simple Armory (%s)",

    -- Source types
    ["Achievement"] = "Logro",
    ["Raid"] = "Banda",
    ["Dungeon"] = "Mazmorra",
    ["Reputation and renown"] = "Reputación y renombre",
    ["Rare and world boss"] = "Raro y jefe del mundo",
    ["Vendor"] = "Vendedor",
    ["Quest"] = "Misión",
    ["Treasure and zone"] = "Tesoro y zona",
    ["PvP"] = "JcJ",
    ["World event"] = "Evento del mundo",
    ["Profession"] = "Profesión",
    ["Class and race"] = "Clase y raza",
    ["Shop and promotion"] = "Tienda y promoción",
    ["Other activities"] = "Otras actividades",

    -- Availability
    ["Obtainable"] = "Obtenible",
    ["Limited time"] = "Por tiempo limitado",
    ["No longer obtainable"] = "Ya no obtenible",

    -- Tooltip
    ["Collected"] = "Conseguida",
    ["Not collected"] = "No conseguida",
    ["Alliance only"] = "Solo Alianza",
    ["Horde only"] = "Solo Horda",
    ["Also resold on the Black Market Auction House"] = "También se revende en la Casa de Subastas Negra",
    ["Click: show it in the Mount Journal"] = "Clic: verla en el diario de monturas",
    ["Not in the game client yet."] = "Todavía no está en el cliente del juego.",

    -- Groups (Simple Armory categories that are not expansions)
    ["Mounts"] = "General",
    ["Limited Time"] = "Por tiempo limitado",
    ["Racial"] = "Raciales",
    ["Professions"] = "Profesiones",
    ["PVP"] = "JcJ",
    ["World Events"] = "Eventos del mundo",
    ["Past Limited Time"] = "Tiempo limitado (pasado)",
    ["Promotion"] = "Promociones",
    ["Other"] = "Otros",
    ["Not in Simple Armory"] = "No está en Simple Armory",

    -- Generic Simple Armory subcategories
    ["Raid Drop"] = "Botín de banda",
    ["Dungeon Drop"] = "Botín de mazmorra",
    ["Reputation"] = "Reputación",
    ["Reputations"] = "Reputaciones",
    ["Paragon Reputation"] = "Reputación de dechado",
    ["Renown"] = "Renombre",
    ["Raid Renown"] = "Renombre de banda",
    ["Rare Spawn"] = "Raro",
    ["World Boss"] = "Jefe del mundo",
    ["Treasure"] = "Tesoro",
    ["Zone Drop"] = "Botín de zona",
    ["Zone Feature"] = "Actividad de zona",
    ["Zone"] = "Zona",
    ["Daily Activities"] = "Actividades diarias",
    ["Campaign"] = "Campaña",
    ["Collect"] = "Coleccionar",
    ["Unknown"] = "Desconocido",
    ["Feats of Strength"] = "Proezas de fuerza",
    ["Allied Races"] = "Razas aliadas",
    ["Allied Race"] = "Raza aliada",
    ["Class Hall"] = "Sede de clase",
    ["Blizzard Store"] = "Tienda de Blizzard",
    ["Guild Vendor"] = "Vendedor de hermandad",
    ["Fishing"] = "Pesca",
    ["Archaeology"] = "Arqueología",
    ["Engineering"] = "Ingeniería",
    ["Tailoring"] = "Sastrería",
    ["Jewelcrafting"] = "Joyería",
    ["Leatherworking"] = "Peletería",
    ["Alchemy"] = "Alquimia",
    ["Blacksmith"] = "Herrería",
    ["Events"] = "Eventos",
    ["Pre-Launch Event"] = "Evento de prelanzamiento",
    ["Heirlooms"] = "Reliquias",
    ["Toys"] = "Juguetes",

    -- Commands
    ["Click to open or close the window."] = "Haz clic para abrir o cerrar la ventana.",
    ["Commands: /matlas (window) | /matlas <text> (search) | /matlas semana | /matlas minimap | /matlas logros"] = "Comandos: /matlas (ventana) | /matlas <texto> (buscar) | /matlas semana | /matlas minimap | /matlas logros",
    ["Minimap button"] = "Botón en el minimapa",

    -- Drop chance (Rarity), lockouts and alts
    ["Drop chance: %s (1/%d)"] = "Probabilidad de botín: %s (1/%d)",
    ["%d attempts"] = "%d intentos",
    ["Good luck! %d attempts so far"] = "¡Suerte! Llevas %d intentos",
    ["Good luck! First attempt"] = "¡Suerte! Primer intento",
    ["Already killed this week on this character"] = "Ya matado esta semana con este personaje",
    ["Already killed today on this character"] = "Ya matado hoy con este personaje",
    ["Available on: "] = "Disponible en: ",
    ["Killed on: "] = "Matado en: ",

    -- What should I farm?
    ["What should I farm?"] = "¿Qué monturas farmeo hoy?",
    ["Raid limit"] = "Límite de bandas",
    ["Raids and dungeons I can do (for \"What should I farm?\")"] = "Bandas y mazmorras que puedo hacer (para «¿Qué monturas farmeo hoy?»)",
    ["Up to %s"] = "Hasta %s",
    ["This list needs the Rarity addon (it has the drop chances). Install it and reload."] = "Esta lista necesita el addon Rarity (tiene las probabilidades de botín). Instálalo y recarga.",
    ["Raid and dungeon mounts you are missing"] = "Monturas de banda y mazmorra que te faltan",
    ["Raid, dungeon, world boss and rare mounts you are missing"] = "Monturas de banda, mazmorra, jefe del mundo y raro que te faltan",
    ["%s, up to %s (Options > Raid limit). Best odds first; bosses you already killed go last."] = "%s, hasta %s (Opciones > Límite de bandas). Primero las de más probabilidad; los jefes que ya has matado van al final.",
    ["World bosses and rares in \"What should I farm?\""] = "Jefes del mundo y raros en «¿Qué monturas farmeo hoy?»",
    ["Message when entering an instance"] = "Aviso al entrar en una instancia",
    ["Mounts you are missing here:"] = "Monturas que te faltan aquí:",
    ["Already killed this week"] = "Ya matado esta semana",
    ["Already killed today"] = "Ya matado hoy",

    -- Weekly summary
    ["Weekly summary"] = "Resumen semanal",
    ["Since the weekly reset on %s."] = "Desde el reinicio semanal del %s.",
    ["Got this week"] = "Conseguidas esta semana",
    ["Nothing yet this week. Keep at it!"] = "Todavía nada esta semana. ¡Ánimo!",
    ["Attempts and lockouts need the Rarity addon."] = "Los intentos y los bloqueos necesitan el addon Rarity.",
    ["Attempts this week"] = "Intentos esta semana",
    ["No attempts recorded this week yet."] = "Aún no hay intentos esta semana.",
    ["%d attempts on %d mounts."] = "%d intentos en %d monturas.",
    ["+%d this week"] = "+%d esta semana",
    ["Total: %d"] = "Total: %d",
    ["Your favorites this week"] = "Tus favoritas esta semana",
    ["Holiday event on now"] = "Evento activo ahora",
    ["No holiday event on now, or you already have its mounts."] = "No hay ningún evento activo ahora, o ya tienes sus monturas.",
    ["One reward a day per character (it resets with the daily reset)."] = "Una recompensa al día por personaje (se reinicia con el reinicio diario).",
    ["The event is not on now."] = "El evento no está activo ahora.",
    ["Mark raid, dungeon or rare mounts as favorites (right-click) to see them here."] = "Marca como favoritas monturas de banda, mazmorra o raro (clic derecho) para verlas aquí.",
    ["Nothing to farm with these settings."] = "Nada que farmear con estos ajustes.",
    ["Killed"] = "Matado",
    ["Available"] = "Disponible",
    ["Take me"] = "Llévame",
    ["Show map"] = "Ver mapa",
    ["Shift-click: show the zone on the map (it has no fixed spot)"] = "Mayús+clic: ver la zona en el mapa (no tiene un sitio fijo)",
    ["That place cannot have a map pin (it is inside an instance). Install TomTom for an arrow."] = "No se puede poner un marcador ahí (está dentro de una instancia). Instala TomTom para tener una flecha.",

    -- Favorites
    ["Favorites"] = "Favoritas",
    ["No favorites yet. Right-click a mount to add it."] = "Aún no tienes favoritas. Haz clic derecho en una montura para añadirla.",
    ["Favorites you are missing"] = "Favoritas que te faltan",
    ["You have all your favorites."] = "Ya tienes todas tus favoritas.",
    ["Killed this week"] = "Matado esta semana",
    ["Killed today"] = "Matado hoy",
    ["Right-click: add to or remove from favorites"] = "Clic derecho: añadir o quitar de favoritas",
    ["Shift-click: set a waypoint"] = "Mayús+clic: poner un marcador en el mapa",

    -- Achievements
    ["Achievement: %s"] = "Logro: %s",
    ["Completed"] = "Completado",
    ["  …and %d more"] = "  …y %d más",
    ["Progress: %d/%d"] = "Progreso: %d/%d",
    ["Ctrl-click: open the achievement"] = "Ctrl+clic: abrir el logro",
    ["Looking up achievements…"] = "Buscando logros…",
    ["I could not find the achievement for this mount."] = "No he encontrado el logro de esta montura.",
    ["Achievements linked to a mount: %d"] = "Logros enlazados con una montura: %d",
}

local active = (GetLocale() == "esES") and esES or nil

ns.L = setmetatable({}, {
    __index = function(_, key)
        return (active and active[key]) or key
    end,
})
