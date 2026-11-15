# Reading Tracker (mobile app)

The reading tracker as an installable phone app: log sessions, time your reading, scan a book's barcode to add it, and see your stats. It works offline once installed.

Your books and sessions from the web tracker (4 books, 40 sessions, as of 15 Nov 2026) are in `seed.js` and load on first launch. After that, the app keeps its own copy on the phone.

## Screens
- **Today**: today, streak, week, month and books finished; the big reading timer; quick "Log pages".
- **Books**: books in progress (log, finish, timer, did not finish, delete), add a book (live barcode scan with ISBN lookup), and the finished / written-off shelf.
- **Stats**: finished this month (spines + calendar), pages read by day/week/month, your average day, books finished per month.
- **Log**: every session by day, plus backup and restore.

## Put it on your phone
1. In GitHub, go to **Settings → Pages**, set **Source** to "Deploy from a branch", pick the branch and `/ (root)`, and save.
2. Open the Pages link on your phone.
   - **iPhone (Safari):** Share → **Add to Home Screen**.
   - **Android (Chrome):** menu ⋮ → **Install app**.

## Barcode scanning
Scanning never worked in the Claude app version: Claude app pages aren't allowed to use the camera. This app runs in your phone's own browser, which can. Tap **Scan the barcode**, allow the camera once, and hold the barcode inside the green box; it reads by itself. If you say no to the camera, it offers to take a photo instead. The barcode reader is bundled with the app (`vendor/zxing.min.js`), so scanning works offline. The book details come from Open Library (then Google Books), which needs a connection.

## Your data
Data is stored on the phone (localStorage), not in the cloud, so it doesn't sync between devices. Use **Log → Save a backup** now and then; **Restore a backup** loads it on another phone.

## Files
`index.html`, `styles.css`, `app.js` (the app), `seed.js` (your data), `manifest.webmanifest` + `icons/` (install), `sw.js` (offline). When you change app files, bump `VERSION` in `sw.js` so installed copies update.
