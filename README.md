# CDSync 🔄 (Cloud Drive Sync)

**Sad because there is no official Google Drive sync client for Linux?**
Tired of the only working solutions being paid services?

**Smile! CDSync is here.**

Keep your cloud drives synced locally for free using a lightweight, automated daemon based on Rclone, Inotify, and Systemd.

---

CDSync is a lightweight, robust, and automated **bidirectional synchronization tool** for Linux users who manage cloud storage via [Rclone](https://rclone.org/).

Unlike the standard `rclone mount` (which streams files) or manual sync scripts, CDSync functions like the official Google Drive/Dropbox clients: it keeps a **physical local copy** of your files and syncs changes in the background using system services.

## 🚀 Features

*   **Real-time Local Monitoring:** Uses `inotify` to detect local changes instantly and push them to the cloud.
*   **Remote Polling:** Periodically checks the cloud for changes to pull updates from other devices (default: every 5 min, but configurable via Tray Menu).
*   **System Tray Icon:** Visual indicator (Active/Stopped) with quick controls, dynamic icons, and configuration menu. Accessible via System Menu.
*   **Desktop Notifications:** Get notified immediately if a sync fails or a manual sync starts.

*   **Systemd Integration:** Runs silently in the background as a user service. Starts automatically on boot.
*   **Smart Filtering:** Includes a `filter-rules.txt` to automatically ignore build artifacts (`node_modules`, `.git`, `venv`, etc.), saving bandwidth and I/O.
*   **Safety Locks:** Implements file locking (mutex) to prevent overlapping sync jobs.
*   **Portable:** Can be installed from any directory.

## 📋 Prerequisites

*   **Rclone**: Configured and working with your desired remote.
*   **System Tools**: `inotify-tools` and Python libraries for the System Tray icon.

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install rclone inotify-tools python3-gi gir1.2-appindicator3-0.1
```

## 🛠️ Installation

1.  Clone this repository:
    ```bash
    git clone https://github.com/muller-front/cdsync.git
    cd cdsync
    ```

2.  **Configuration**:
    Copy the template and edit your settings:
    ```bash
    cp config.env.example config.env
    nano config.env
    ```
    *   Set `RCLONE_REMOTE` (e.g., `gdrive:`).
    *   Set `LOCAL_SYNC_DIR` (absolute path to your local folder).
    *   **(Optional)** Set `POLL_INTERVAL` (default: 5 min).

3.  **Install Services**:
    Run the installer script. It will check connections, install systemd services, and ask if you want to start them immediately.
    ```bash
    ./install.sh
    ```

## 🚀 First Run Recommendation
If you are setting this up for the first time, or if your local folder differs significantly from the cloud:
1.  Choose **No** when asked to start services during installation.
2.  Start the **Tray Icon**.
3.  Open the menu and select **"🔧 Force Resync (Repair)"**.
    *   This ensures the synchronization database is built correctly without errors.

## ⚙️ Managing Configuration

### Changing Sync Interval
To change how often CDSync checks for remote changes:
1.  **Tray Icon** -> **⚙️ Config** -> **⏱️ Set Interval...**.
2.  Enter the new duration in minutes. The system will update and reload automatically.

### Ignoring Files (Filters)
Edit `filter-rules.txt` to add patterns to exclude (e.g., `node_modules`, `*.tmp`).

## ❓ Troubleshooting

### "Sync Failed" / Stale Lock
If a sync crashes or the computer shuts down unexpectedly, a lock file might be left behind.
*   **Solution**: **Tray Icon** -> **⚙️ Config** -> **🔧 Force Resync (Repair)**. It fixes the database and clears stale locks.

### "Files Deleted" in Activity Log?
If you see "Deleted" events for files you didn't touch:
*   Check if the file was removed from the **Remote (Google Drive/Dropbox)**.
*   CDSync mirrors the remote state. If it's gone there, it gets removed locally.
*   Check your Cloud Trash bin to recover them.

## 🗑️ Uninstallation

To stop services and remove them from systemd:
```bash
./uninstall.sh
```

## 📄 License

This project is distributed under the MIT License. See the `LICENSE` file for more details.
