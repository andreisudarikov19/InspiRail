# 🚨 QUICK FIX: Delete Simulator Database

## The Issue

The database migration error is happening because the old database files exist in the simulator with the old schema. The auto-reset code tries to delete them, but SwiftData has already locked them during initialization.

## ✅ Solution: Delete Database Manually

### Option 1: Reset Entire Simulator (Easiest)

In Xcode Simulator menu:
```
Device → Erase All Content and Settings
```

Then rebuild: `⌘R`

### Option 2: Delete Just the Database Files (Terminal)

```bash
# Find the database location (from your logs):
cd "/Users/andreisudarikov/Library/Developer/CoreSimulator/Devices/8FF5B33B-BA21-4D46-985B-43ADFA6E29D2/data/Containers/Data/Application/ED54788C-E538-4787-B1F4-EEB850FB1FAE/Library/Application Support"

# Delete database files
rm default.store
rm default.store-wal
rm default.store-shm

# Rebuild app
```

### Option 3: Delete All Sim Databases (Clean Slate)

```bash
# This removes all app data from all simulators
xcrun simctl erase all
```

Then rebuild: `⌘R`

### Option 4: Uninstall App from Simulator

1. **Long-press the app icon** in simulator
2. **Click the (-)** to delete
3. **Rebuild** in Xcode: `⌘R`

## 📊 Expected Result

After deleting and rebuilding, you should see:

```
✅ Successfully created new ModelContainer
(No CoreData errors)
✅ Backend connection successful!
```

## Why Auto-Reset Didn't Work

The logs show:
```
❌ Failed to create ModelContainer: SwiftData.SwiftDataError error 1
⚠️ Falling back to in-memory database
```

The problem: **SwiftData locks the database files during init**, BEFORE our error handler can delete them. By the time we catch the error, the files are locked and can't be deleted.

The app then falls back to in-memory mode (data doesn't persist), which is why it "works" but the error keeps appearing on each launch.

## 🎯 After Manual Delete

The database files will be gone, so on next launch:
1. ✅ No old database to migrate
2. ✅ SwiftData creates fresh database  
3. ✅ New schema (`isFavorite` field) works
4. ✅ No errors, persistent storage works

## Quick Command

```bash
# One-liner to reset simulator and rebuild
xcrun simctl erase all && xcodebuild -scheme rnsapp clean build
```

Then just `⌘R` in Xcode!
