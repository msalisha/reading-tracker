# Pageturner for iPhone

**Pageturner** is a native SwiftUI app (iOS 17+) rebuilt from the web Reading Tracker, ready to sell on the App Store as a free download with a **3-day free trial** and a **one-off unlock**.

## What's in it

| Tab | What you can do |
|---|---|
| **Today** | Scores (today, streak, week, month, books finished), the reading timer (choose a book, set the starting page, start, pause, Done, log the page you got to), log a session by hand, books on the go |
| **Books** | On the go (progress, pace, reading line, timer with pause/resume), **Want to read**, the shelf (finished and written off). **Add a book** by scanning its barcode (finds the title, author, pages and **cover**) or typing it |
| **Book page** | Cover, progress, **star rating** (optional, half stars), **notes**: quotes and thoughts with an optional page number, **scan a quote from the page** with the camera, copy and share, edit details |
| **Stats** | Finished this month (spines and calendar), pages by day, week or month, your average day, books per month and average rating |
| **Log** | Every session by day (swipe to delete), plus **search across all your notes** |
| **Settings** | **6 colour schemes** (the app icon changes to match), light/dark, purchase and Restore, import and export a backup (JSON), spreadsheet export (CSV) |

Outside the app:
- **Lock screen and Dynamic Island:** the timer, with Pause and Resume buttons.
- **Widgets:** streak (home screen and lock screen) and current book (with a Start timer button).

**Your data:** your web Reading Tracker backup imports straight in (Settings → Import a backup). The unit tests import your actual 4 books and 40 sessions to prove it.

## First run on your Mac

1. Install Xcode (from the Mac App Store) and XcodeGen: `brew install xcodegen`
2. Get the code: `git clone https://github.com/msalisha/reading-tracker && cd reading-tracker/ios`
3. Open `project.yml` and set:
   - `APP_BUNDLE_ID`: your own reverse-domain id, e.g. `com.yourname.pageturner` (it's `com.example.pageturner` until you change it)
   - `APP_DISPLAY_NAME`: the name under the icon (already `Pageturner`)
   - `DEVELOPMENT_TEAM`: your Team ID (Xcode → Settings → Accounts, or developer.apple.com → Membership)
4. `xcodegen` creates `ReadingTracker.xcodeproj`. Open it.
5. Choose your iPhone as the run destination and press **Run**. The trial and purchase use the local `ReadingTracker.storekit` file, so nothing is charged while testing.

Re-run `xcodegen` whenever files are added or `project.yml` changes.

**Testing the trial in Xcode:** Debug → StoreKit → Manage Transactions shows the trial and unlock. Delete them to start again. To see the "trial ended" screen without waiting 3 days, run with the launch argument `-access expired` (Product → Scheme → Edit Scheme → Arguments). Other values are `trial`, `unlocked` and `none`. Add `-uitest -uitest-sample` to see a sample library.

## Putting it on the App Store

### In App Store Connect (appstoreconnect.apple.com)
1. **Certificates, Identifiers & Profiles** (developer.apple.com):
   - Register the App ID (your `APP_BUNDLE_ID`) with **App Groups** turned on.
   - Create the group `group.<your bundle id>`.
   - Register `<bundle id>.widgets` with the same group.
   - Xcode's automatic signing can do all of this for you on first run.
2. **My Apps → +** New App: platform iOS, name **Pageturner** (if it's taken, try *Pageturner: Reading Tracker* or *Pageturner – Reading Log*; the name under the icon can stay Pageturner), primary language, the bundle ID, and a SKU (anything, e.g. `pageturner-1`).
3. **In-App Purchases** (Monetization → In-App Purchases), create two **Non-Consumable** items:

   | Product ID | Reference name | Price | Display name | Description |
   |---|---|---|---|---|
   | `trial.3day` | 3-Day Free Trial | **Free** | 3-Day Free Trial | Use every feature free for 3 days. |
   | `unlock.lifetime` | Unlock forever | e.g. £4.99 | Unlock forever | Unlock everything, forever. One payment, no subscription. |

   Apple requires the free item's name to say how long the trial is ("3-Day Free Trial"). Add a review screenshot to each item; the paywall screenshot works.
4. **App Privacy:** choose **Data Not Collected**.
5. **Privacy Policy URL:** `https://msalisha.github.io/reading-tracker/privacy.html`
   **Support URL:** `https://msalisha.github.io/reading-tracker/support.html`
6. **Category:** Books (secondary: Lifestyle or Productivity). **Age rating:** 4+.

### Upload and test
1. In Xcode: set the destination to **Any iOS Device**, then Product → **Archive** → Distribute App → App Store Connect.
2. Install from **TestFlight** on your phone. Check the camera scanning, the lock-screen timer and the widgets on a real device.
3. In the version page: add screenshots, the description, keywords and the in-app purchases, then **Submit for Review**.

### Screenshots
CI saves screenshots of the sample library on every run (Actions → the run → **ios-results** artifact). For the App Store sizes, run the `FlowUITests/testScreenshots` test on an **iPhone 16 Pro Max** (6.9") simulator in Xcode, then use the images from the test report.

### Notes for the App Review team (paste into "Notes")
> This app is a free download with a 3-day free trial, then a one-off non-consumable purchase ("Unlock forever"). Following guideline 3.1.1, the trial is a free non-consumable in-app purchase named "3-Day Free Trial", started from the welcome screen. After 3 days, all previously entered data stays visible and exportable (read-only); adding or logging shows the unlock screen. "Restore purchases" is in Settings. The camera is used only for barcode and quote scanning on-device. No account or login is needed.

### Suggested App Store text
- **Subtitle (30 chars):** Reading timer, notes & stats
- **Keywords (100 chars):** reading tracker,book log,reading timer,pages,streak,quotes,bookshelf,reading goals,book journal
- **Promotional text:** Time your reading on the lock screen, keep your favourite quotes, and watch your streak grow.
- **Description:**
  > Track every page you read.
  >
  > • Reading timer, right on your lock screen and Dynamic Island, with pause and resume
  > • Scan a book's barcode to add it, with its cover
  > • Keep quotes and thoughts for every book, and scan a quote straight from the page
  > • Rate the books you finish
  > • Streaks, pages a day, pace, and how long until you finish
  > • A shelf of everything you've finished this month
  > • Want to read list
  > • Home-screen and lock-screen widgets
  > • Six colour schemes, each with a matching app icon
  > • Your reading stays on your iPhone. No account, no ads, no tracking.
  >
  > Try everything free for 3 days, then unlock it forever with one payment. No subscription.

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
