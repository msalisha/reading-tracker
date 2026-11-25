# Pageturner for iPhone

**Pageturner** is a native SwiftUI app (iOS 17+) rebuilt from the web Reading Tracker, ready to sell on the App Store as a free download with a **3-day free trial** and a **one-off unlock**.

## What's in it

| Tab | What you can do |
|---|---|
| **Today** | Scores (today, streak, week, month, books finished), the reading timer (choose a book, set the starting page, start, pause, Done, log the page you got to) with optional **Focus sounds** (rain, café or fireplace, keeps playing with the screen locked), log a session by hand, books on the go |
| **Books** | On the go (progress, pace, reading line, timer with pause/resume), **Want to read**, the shelf (finished and written off). **Add a book** by scanning its barcode (finds the title, author, pages and **cover**) or typing it. **Audiobooks** too: length and position in hours and minutes, with listening time counted separately from pages |
| **Book page** | Cover (tap it to use the ISBN's cover, **search Google Images** inside the app, choose from Photos or take a photo), progress, **star rating** (optional, half stars), **notes**: quotes and thoughts with an optional page number, **scan a quote from the page** with the camera, **share any quote as a picture** in six styles (Poster, Collage, Dreamy, Highlighter, Editorial, Bookmark), three sizes and any colour scheme, copy, edit details |
| **Stats** | **Monthly recap** and **Year in review** (story-style pages you can swipe and share as pictures), finished this month (spines and calendar), pages by day, week or month, your average day, books per month and average rating |
| **Log** | Every session by day (swipe to delete), plus **search across all your notes** |
| **Settings** | **6 colour schemes** (the app icon changes to match), light/dark, purchase and Restore, **iCloud sync** status, import and export a backup (JSON), **import from Goodreads**, spreadsheet export (CSV) |

Outside the app:
- **Lock screen and Dynamic Island:** the timer, with Pause and Resume buttons.
- **Widgets:** streak (home screen and lock screen) and current book (with a Start timer button).

**iCloud sync:** books, sessions, notes and covers sync across the user's iPhone and iPad through their private iCloud (SwiftData + CloudKit). If the same book ends up on two devices (e.g. one backup imported on both), the copies are merged automatically, keeping every session and note.

**Your data:** your web Reading Tracker backup imports straight in (Settings → Import a backup). The unit tests import your actual 4 books and 40 sessions to prove it.

## First run on your Mac

1. Install Xcode (from the Mac App Store) and XcodeGen: `brew install xcodegen`
2. Get the code: `git clone https://github.com/msalisha/reading-tracker && cd reading-tracker/ios`
3. Open `project.yml` and set:
   - `APP_BUNDLE_ID`: already set to `com.alishasutcliffe.pageturner`. Don't change it after release: the App Store listing, purchases and iCloud data are tied to it.
   - `APP_DISPLAY_NAME`: the name under the icon (already `Pageturner`)
   - `DEVELOPMENT_TEAM`: your Team ID (Xcode → Settings → Accounts, or developer.apple.com → Membership)
4. `xcodegen` creates `ReadingTracker.xcodeproj`. Open it.
5. In Xcode, select the **ReadingTracker** target → **Signing & Capabilities**. Under **iCloud**, make sure the container `iCloud.<your bundle id>` is ticked (if the list is empty, press **+** and add exactly that name, or click the ↻ refresh button). This needs a paid Apple Developer Program membership.
6. Choose your iPhone as the run destination and press **Run**. The trial and purchase use the local `ReadingTracker.storekit` file, so nothing is charged while testing.

Re-run `xcodegen` whenever files are added or `project.yml` changes.

**Before TestFlight or the App Store:** deploy the iCloud schema (see "Putting it on the App Store", step 5).

**If "Start my 3-day free trial" fails while testing from Xcode:**
- The message now says why. If it mentions **Screen Time**, turn on in-app purchases: iPhone **Settings → Screen Time → Content & Privacy Restrictions → iTunes & App Store Purchases → In-app Purchases → Allow**.
- In Xcode, check **Product → Scheme → Edit Scheme… → Run → Options → StoreKit Configuration** says **ReadingTracker.storekit**. If it says None, choose it from the list.
- In testing builds, the error box offers **Unlock for testing**. You can also add `-access unlocked` under **Run → Arguments**. Neither exists in the App Store version.
- Anyone can tap **Look around first** to browse the app read-only without starting the trial.

**Testing the trial in Xcode:** Debug → StoreKit → Manage Transactions shows the trial and unlock. Delete them to start again. To see the "trial ended" screen without waiting 3 days, run with the launch argument `-access expired` (Product → Scheme → Edit Scheme → Arguments). Other values are `trial`, `unlocked` and `none`. Add `-uitest -uitest-sample` to see a sample library.

## Using it yourself

- **From Xcode** (what you have now): a development build. With a paid account it works for about a year; press ▶︎ again to renew or update. Purchases are free test purchases, and the error box offers **Unlock for testing**.
- **From TestFlight** (recommended, no cable): upload a build as described below, add yourself under **TestFlight → Internal Testing**, then install from the TestFlight app. TestFlight purchases are free, so tap **Unlock forever**. Each build lasts 90 days.
- **From the App Store** after launch: install it like anyone else; it replaces the TestFlight copy and keeps your library. Unlock it by buying it, or with a free **offer code** you create for `unlock.lifetime` in App Store Connect.

**iCloud and switching builds:** your library always stays on the phone, but builds run from Xcode sync with iCloud's *Development* area, while TestFlight and App Store copies use *Production*. Deploy the schema (step 5 below) before installing from TestFlight, and save a backup first (Settings → Save a backup) to be safe. The TestFlight copy then uploads your library to Production, and your other devices pick it up from there.

## Putting it on the App Store

### 1. One-off setup (App Store Connect → appstoreconnect.apple.com)
1. **Business → Agreements:** accept the **Paid Applications** agreement and add your bank and tax details. In-app purchases (including the free trial) don't work, even for Apple's reviewers, until this is active. Consider the **Small Business Program** (15% commission instead of 30%).
2. **Bundle ID:** `APP_BUNDLE_ID` in `project.yml` is `com.alishasutcliffe.pageturner`. Set `DEVELOPMENT_TEAM` to your Team ID and run the app from Xcode once. Automatic signing registers the App ID, the App Group, the widget extension and the iCloud container `iCloud.<bundle id>`.
3. **My Apps → +** New App: iOS, name **Pageturner** (if it's taken: *Pageturner: Reading Tracker* or *Pageturner – Reading Log*; the name under the icon stays Pageturner), your bundle ID, any SKU (e.g. `pageturner-1`).
4. **In-App Purchases** (Monetization → In-App Purchases), two **Non-Consumable** items:

   | Product ID | Reference name | Price | Display name | Description |
   |---|---|---|---|---|
   | `trial.3day` | 3-Day Free Trial | **Free** | 3-Day Free Trial | Use every feature free for 3 days. |
   | `unlock.lifetime` | Unlock forever | **9.99** (the matching price point in each currency, e.g. £9.99 / $9.99 / €9.99) | Unlock forever | Unlock everything, forever. One payment, no subscription. |

   Apple requires the free item's name to say how long the trial is ("3-Day Free Trial"). Each item needs a review screenshot; the paywall screenshot works.
5. **iCloud schema:** after running the app from Xcode at least once on a device signed in to iCloud, open [CloudKit Console](https://icloud.developer.apple.com) → container `iCloud.<bundle id>` → **Deploy Schema Changes…** (Development → Production). Sync won't work in TestFlight or the App Store until this is done. Repeat after any change to the data models.
6. **App Privacy:** **Data Not Collected** (iCloud sync uses the customer's own private iCloud, which you can't access).
   - **Privacy Policy URL:** `https://msalisha.github.io/reading-tracker/privacy.html`
   - **Support URL:** `https://msalisha.github.io/reading-tracker/support.html`
   - **Category:** Books (secondary: Lifestyle or Productivity). **Age rating:** 4+.
   - Export compliance is already answered in the app (`ITSAppUsesNonExemptEncryption = NO`).

### 2. Upload and test
1. In Xcode, choose **Any iOS Device (arm64)** as the destination, then **Product → Archive**. In the Organizer: **Distribute App → App Store Connect → Upload**. (For each later upload, raise `CURRENT_PROJECT_VERSION` in `project.yml`, and `MARKETING_VERSION` for a new release.)
2. After 10–30 minutes the build appears under **TestFlight**. Add yourself to **Internal Testing** and install it from the TestFlight app.
3. Check on a real device: barcode and quote scanning, the lock-screen timer and Dynamic Island, widgets, Focus sounds with the screen locked, iCloud sync to a second device, starting the trial and buying the unlock (free in TestFlight).

### 3. The version page, then submit
1. **Screenshots:** every CI run uploads a ready-made set as the **app-store-screenshots** artifact (GitHub → Actions → the latest "iOS app" run → Artifacts). They're taken on the largest iPhone (6.9", 1320 × 2868) with a tidy 9:41 status bar, which is the size App Store Connect asks for: Today with the timer, a quote card, the monthly recap, the library, a book page, stats, plus the welcome screen.
2. Paste the text below, select the build, and attach **both in-app purchases** to the version (they're reviewed together with the first version).
3. Paste the review notes, then **Submit for Review**. Review usually takes 1–3 days. If something is rejected, Apple explains why in App Store Connect.
4. Choose whether to release automatically once approved, or manually.

### Notes for the App Review team (paste into "Notes")
> This app is a free download with a 3-day free trial, then a one-off non-consumable purchase ("Unlock forever"). Following guideline 3.1.1, the trial is a free non-consumable in-app purchase named "3-Day Free Trial", started from the welcome screen; "Look around first" lets you browse without starting it. After 3 days, all previously entered data stays visible and exportable (read-only); adding or logging shows the unlock screen. "Restore purchases" is in Settings. The camera is used only for barcode and quote scanning, processed on-device. Library data syncs through the user's own private iCloud database (can be switched off in Settings). Cover search opens Google Images in an in-app browser; nothing is sent except the search terms. "Import from Goodreads" reads a CSV file the user exports from Goodreads themselves; it is processed on-device and the app never contacts Goodreads. No account or login is needed.

### Suggested App Store text
- **Subtitle (30 chars):** Reading timer, notes & stats
- **Keywords (100 chars):** reading tracker,book log,reading timer,audiobook,goodreads,streak,quotes,book journal,recap
- **Promotional text:** Time your reading and listening, turn favourite quotes into beautiful cards, and get a monthly recap. Bring your Goodreads library with you.
- **Description:**
  > Track every page you read.
  >
  > • A reading timer right on your lock screen and Dynamic Island, with pause and resume
  > • Focus sounds while you read: rain, café, fireplace, beach or soft noise
  > • Scan a book's barcode to add it with its cover, or find any cover with Google Images
  > • Keep quotes and thoughts for every book, and scan a quote straight from the page
  > • Share quotes as beautiful cards in six styles, sized for stories and posts
  > • Audiobooks too: track listening time alongside pages
  > • Import your library from Goodreads, with ratings and reviews
  > • Rate the books you finish, and keep a Want to read list
  > • Streaks, pages a day, pace, and how long until you finish
  > • A monthly recap and a Year in review you can swipe through and share
  > • Home-screen and lock-screen widgets
  > • Six colour schemes, each with a matching app icon
  > • Syncs across your iPhone and iPad with iCloud. No account, no ads, no tracking.
  >
  > Try everything free for 3 days, then unlock it forever with one payment. No subscription.

## Tech stack

- **Swift 6** with complete data-race checking. The compiler proves there are no threading bugs.
- **SwiftUI** (iOS 17+), with iOS 26 **Liquid Glass** on newer phones: the tab bar shrinks while you scroll, plus glass buttons and controls.
- **SwiftData** for storage, synced with **CloudKit** (the user's private iCloud database); **Swift Charts**; **StoreKit 2** for the trial and purchase.
- **VisionKit** for barcode and quote scanning; **PhotosUI** and the camera for covers.
- **WidgetKit**, **ActivityKit** (Live Activities) and **App Intents** for widgets and the lock-screen timer.
- **AVAudioEngine** for the generated stereo Focus sounds.
- **Swift Testing** for the logic tests; XCTest UI tests.
- CI builds with the newest Xcode on GitHub's Mac runners.

The minimum is iOS 17, so iPhones from 2018 (XS/XR) onwards can buy it. Phones on iOS 26 get the new design automatically.

## Project layout

```
ios/
  project.yml              XcodeGen spec (bundle id, name, team, targets)
  Shared/                  Code used by the app and the widgets: stats maths, dates, themes, timer, Live Activity
  ReadingTracker/          The app: models (SwiftData), logic, store (StoreKit 2), views
  ReadingWidgets/          Widgets and the lock-screen Live Activity
  ReadingTrackerTests/     Unit tests (stats, ISBN, trial rules, importing the web backup)
  ReadingTrackerUITests/   UI tests and screenshots
```

**CI:** every push that touches `ios/` builds the app and runs all tests on an iPhone simulator in GitHub Actions (`.github/workflows/ios.yml`).
