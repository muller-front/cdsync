# CDSync 🔄 (Cloud Drive Sync)

**Sad because there is no official Google Drive sync client for Linux?**  
Tired of the only working solutions being paid services? 💸

**Smile! CDSync is here.** 😃✨

Keep your cloud drives synced locally for free using a lightweight, automated daemon that works just like the official clients you miss.

---

## 🚀 Why CDSync?

Unlike other tools that just "mount" your drive (making it slow) or require manual commands, **CDSync** gives you a **real physical copy** of your files.
*   **Offline Access**: Your files are always there, even without internet.
*   **Instant Upload**: Save a file, and *woosh* 💨! It's in the cloud instantly.
*   **Battery Friendly**: It sleeps when you do. No heavy background processes draining your laptop.

## ✨ Magic Features (v1.6)

*   **⚡ Instant Smart Sync**: Changed a file? CDSync detects it instantly and uploads *only* that file. No scanning the whole drive. It's fast, efficient, and magic.
*   **🧠 Anti-Loop Brain**: The system is smart enough to know the difference between *you* changing a file and *it* downloading a file. No more infinite sync loops!
*   **🛡️ Conflict Highlander Mode**: You decide: "There can be only one" (Newer wins) or "Safety First" (Keep both).
*   **🎨 Beautiful Tray Icon**: A sleek icon in your system bar tells you everything:
    *   🟢 **Green**: All good, system active.
    *   🔴 **Red**: System stopped.
    *   ⚡ **Lightning**: Syncing right now!
    *   📁 **Activity Log**: See exactly what files were added (✅), deleted (🗑️), or updated (🔄).

---

## 🎮 How to Use (The Tray Icon)

Once installed, a little **CDSync** icon lives in your system tray. Click it to control everything!

### 🖱️ Main Menu
*   **CDSync: 🟢/🔴**: Click to Turn On/Off. Like a light switch.
*   **📜 Activity**: Hover to see the last 10 things that happened.
*   **Sync Now**: Forces a check (just in case).

### ⚙️ Config Menu (Power User Stuff)
*   **⏱️ Set Interval...**: How often should we check the cloud for changes? (Default: 5 mins).
*   **🔔 Notifications**: Too noisy? Set it to **⚠️ Errors Only** or silence it completely (🔴).
*   **⚔️ Force Sync Newer**:
    *   🔘 **On**: If there's a conflict, the newer file overwrites the old one. Clean and simple.
    *   ⛔ **Off**: Safety mode. Keeps both files (creates a backup).

---

## 🛠️ Installation (Easy Mode)

1.  **Get the code**:
    ```bash
    git clone https://github.com/muller-front/cdsync.git
    cd cdsync
    ```

2.  **Configure**:
    Copy the template and tell us where your files are:
    ```bash
    cp config.env.example config.env
    nano config.env
    ```
    *   `RCLONE_REMOTE`: Your cloud drive name (e.g., `gdrive:`).
    *   `LOCAL_SYNC_DIR`: Where you want your files on your computer.

3.  **Install**:
    Run the magic script:
    ```bash
    ./install.sh
    ```
    It will set up everything to start automatically when you turn on your computer.

---

## ❓ Troubleshooting (FAQ)

**"I see 'Deleted' in the log but I didn't delete anything!"** 😱
Don't panic! CDSync creates a mirror. If a file is removed from the Cloud (Google Drive/Dropbox), it is removed from your computer too. Check your cloud Trash bin!

**"It's stuck!"**
Go to **⚙️ Config** -> **🔧 Force Resync (Repair)**. This fixes 99% of problems by rebuilding the database.

---

## 📜 What's New in v1.6?
*   **Smart Anti-Echo**: Replaced the "Blindfold" with a "Smart Ignore List". The system now knows exactly which files it touched.
*   **Notification Levels**: You can now mute the notifications. 🤫
*   **Conflict Toggle**: Added the "Highlander" switch. ⚔️
*   **Visual Polish**: New icons for everything. It looks great!

## 📄 License
MIT License. Free and Open Source forever. ❤️
