extension Strings {
    /// The screenshot tool: the toolbar, the toasts, the menu and Productivity tools › Screenshots.
    static let ruScreenshots: [String: String] = [
        // Menu
        "Take a Screenshot…": "Сделать снимок экрана…",
        "Screenshot the Full Screen": "Снимок всего экрана",
        "Screenshot the Last Rectangle": "Снимок последней области",
        // Toolbar
        "Rectangle (R)": "Прямоугольник (R)",
        "Lasso (L)": "Лассо (L)",
        "The screen under the cursor (W)": "Экран под курсором (W)",
        "All screens (A)": "Все экраны (A)",
        "Box": "Рамка",
        "Arrow": "Стрелка",
        "Highlight": "Выделение цветом",
        "Blur": "Размытие",
        "Freehand blur": "Размытие кистью",
        "Box (B)": "Рамка (B)",
        "Arrow (→)": "Стрелка (→)",
        "Highlight (H)": "Выделение цветом (H)",
        "Blur rectangle (X)": "Размыть прямоугольник (X)",
        "Freehand blur (F)": "Размытие кистью (F)",
        "Undo the last mark (⌘Z)": "Отменить последнюю пометку (⌘Z)",
        "Copy it (⏎ or ⌘C)": "Скопировать (⏎ или ⌘C)",
        "Save it (⏎)": "Сохранить (⏎)",
        "Copy and save it (⏎)": "Скопировать и сохранить (⏎)",
        "Save it to the folder (⌘S)": "Сохранить в папку (⌘S)",
        "Cancel (⎋)": "Отмена (⎋)",
        "Red (1)": "Красный (1)",
        "Yellow (2)": "Жёлтый (2)",
        "Green (3)": "Зелёный (3)",
        "Blue (4)": "Синий (4)",
        "White (5)": "Белый (5)",
        "Black (6)": "Чёрный (6)",
        "DRAG AN AREA · W SCREEN · A ALL SCREENS · ⏎ THE WHOLE SCREEN · ⎋ CANCEL":
            "ВЫДЕЛИ ОБЛАСТЬ · W ЭКРАН · A ВСЕ ЭКРАНЫ · ⏎ ВЕСЬ ЭКРАН · ⎋ ОТМЕНА",
        "DRAW A LOOP AROUND IT · ⏎ THE WHOLE SCREEN · ⎋ CANCEL": "ОБВЕДИ ПЕТЛЁЙ · ⏎ ВЕСЬ ЭКРАН · ⎋ ОТМЕНА",
        "%@ · 1–6 COLOUR · ⌘Z UNDO · ⏎ COPY · ⌘S SAVE · ⎋ CANCEL": "%@ · 1–6 ЦВЕТ · ⌘Z ОТМЕНИТЬ · ⏎ КОПИЯ · ⌘S СОХРАНИТЬ · ⎋ ОТМЕНА",
        // Text
        "Text": "Текст",
        "Add text (T)": "Добавить текст (T)",
        "Choose the font (⌘F for the next one)": "Выбрать шрифт (⌘F — следующий)",
        "Smaller text (⌘−)": "Текст мельче (⌘−)",
        "Bigger text (⌘+)": "Текст крупнее (⌘+)",
        "Turn the text %@° left (⌘[)": "Повернуть текст на %@° влево (⌘[)",
        "Turn the text %@° right (⌘])": "Повернуть текст на %@° вправо (⌘])",
        "%@ font (⌘F for the next one)": "Шрифт «%@» (⌘F — следующий)",
        "System": "Системный",
        "Rounded": "Округлый",
        "Monospaced": "Моноширинный",
        "Serif": "С засечками",
        "Handwriting": "Рукописный",
        "TYPING · ⇧⏎ NEW LINE · ⏎ DONE · ⎋ DROP IT · ⌘[ ⌘] TURN · ⌘− ⌘+ SIZE · ⌘F FONT":
            "ПЕЧАТАЕШЬ · ⇧⏎ НОВАЯ СТРОКА · ⏎ ГОТОВО · ⎋ УБРАТЬ · ⌘[ ⌘] ПОВОРОТ · ⌘− ⌘+ РАЗМЕР · ⌘F ШРИФТ",
        "DRAG TO MOVE · TOP HANDLE TURNS (⇧ IN STEPS) · CORNER SIZES · CLICK TO TYPE · ⌫ DELETE · ⎋ DONE":
            "ТАЩИ, ЧТОБЫ ДВИГАТЬ · ВЕРХНЯЯ РУЧКА ПОВОРАЧИВАЕТ (⇧ ШАГАМИ) · УГОЛ МЕНЯЕТ РАЗМЕР · ЩЕЛЧОК — ПЕЧАТАТЬ · ⌫ УДАЛИТЬ · ⎋ ГОТОВО",
        "TEXT · CLICK TO TYPE · CLICK A TEXT TO CHANGE IT · ⌘Z UNDO · ⇧⌘Z REDO · ⏎ COPY · ⎋ CANCEL":
            "ТЕКСТ · ЩЕЛЧОК — ПЕЧАТАТЬ · ЩЕЛЧОК ПО ТЕКСТУ — ИЗМЕНИТЬ · ⌘Z ОТМЕНИТЬ · ⇧⌘Z ВЕРНУТЬ · ⏎ КОПИЯ · ⎋ ОТМЕНА",
        // Toasts and trouble
        "Copied %@": "Скопировано %@",
        "Saved %@": "Сохранено: %@",
        "Copied %@ and saved %@": "Скопировано %@ и сохранено: %@",
        "Ledgelings needs Screen Recording to take screenshots (System Settings › Privacy & Security).":
            "Для снимков экрана Ledgelings нужна запись экрана (Системные настройки › Конфиденциальность и безопасность).",
        "No screen to take.": "Нечего снимать: экранов нет.",
        "The picture could not be made.": "Не получилось собрать картинку.",
        "Could not save to %@: %@": "Не удалось сохранить в %@: %@",
        // Settings
        "Screenshots": "Снимки экрана",
        "Screenshot tool": "Снимки экрана",
        "Needs Screen Recording, to see the screen. Until then a shot only says so.":
            "Нужна запись экрана, чтобы видеть экран. А пока снимок только скажет об этом.",
        "Every screen freezes and dims; drag an area (R), draw a loop (L), or take the screen (W) or all of them (A). Then box (B), arrow (→), highlight (H), blur (X), blur by hand (F) or text (T), in six colours (1–6); ⌘Z undoes, ⇧⌘Z redoes. ⏎ takes it, ⌘C copies, ⌘S saves, ⎋ lets go. Pictures only, never video; nothing leaves this Mac.":
            "Все экраны замирают и темнеют; выдели область (R), обведи петлёй (L) или возьми экран (W) или все сразу (A). Потом рамка (B), стрелка (→), выделение цветом (H), размытие (X), размытие кистью (F) или текст (T), шесть цветов (1–6); ⌘Z отменяет, ⇧⌘Z возвращает. ⏎ готово, ⌘C копирует, ⌘S сохраняет, ⎋ отпускает. Только картинки, без видео; ничего не уходит с этого Mac.",
        "Capture with the toolbar": "Снимок с панелью",
        "Full screen at once": "Весь экран сразу",
        "Full screen takes": "Весь экран — это",
        "All screens, in one picture": "Все экраны, одной картинкой",
        "The screen under the cursor": "Экран под курсором",
        "The last rectangle again": "Последняя область ещё раз",
        "They work in every app. Full screen and the last rectangle go straight to the clipboard or the folder, with no toolbar; with no rectangle taken yet, the last-rectangle keys open the toolbar. All monitors are stitched at each one's own sharpness.":
            "Работают в любом приложении. Весь экран и последняя область сразу уходят в буфер обмена или в папку, без панели; пока области не было, её сочетание открывает панель. Все мониторы склеиваются, каждый в своей чёткости.",
        "Copy to the clipboard": "Копировать в буфер обмена",
        "Save to a folder": "Сохранять в папку",
        "Folder": "Папка",
        "Choose…": "Выбрать…",
        "Choose": "Выбрать",
        "Where a shot goes": "Куда идёт снимок",
        "As a PNG named for its time (Screenshot 2026-10-18 14.03.22.png); the folder is made on the first save. ⌘C on the toolbar only copies, ⌘S always saves. A copy also lands in the clipboard history.":
            "Как PNG с временем в имени (Screenshot 2026-10-18 14.03.22.png); папка создаётся при первом сохранении. ⌘C на панели только копирует, ⌘S всегда сохраняет. Копия попадает и в историю буфера обмена.",
        "Line thickness": "Толщина линии",
        "Colour": "Цвет",
        "Marks": "Пометки",
        "Boxes and arrows are this thick; blurring by hand is four times as wide. A blur is big square blocks, baked into the picture, so the words under it cannot be read back. The toolbar starts on the last colour picked.":
            "Такой толщины рамки и стрелки; кисть размытия вчетверо шире. Размытие — крупные квадраты, впечённые в картинку, так что слова под ним не прочитать. Панель начинает с последнего выбранного цвета.",
        "Font": "Шрифт",
        "Size": "Размер",
        "An outline, so it reads on any background": "Обводка, чтобы читалось на любом фоне",
        "Turn in steps of": "Поворот шагами по",
        "Click a text to change it: drag it, turn it by the handle above it (⇧ in steps), size it by its corner. A new one starts in the last font and size used.":
            "Щёлкни по тексту, чтобы его изменить: тащи его, поворачивай за ручку над ним (с ⇧ шагами), меняй размер за угол. Новый начинается с последних шрифта и размера.",
        "Hide the creatures while capturing": "Прятать существ во время снимка",
        "A creature brings the shot home": "Существо уносит снимок домой",
        "Hidden, they are out of the picture too. Once it is taken, one hops up to where the toolbar was and carries a tiny picture of it back to its edge.":
            "Спрятанные, они не попадают и в кадр. Когда снимок готов, одно запрыгивает туда, где была панель, и уносит крошечную картинку к своему краю.",
    ]
}
