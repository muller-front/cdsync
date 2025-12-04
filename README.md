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
*   **Remote Polling:** Periodically checks the cloud for changes to pull updates from other devices (default: every 5 min, but configurable).

*   **System Tray Icon:** Visual indicator (Active/Stopped) with quick controls to Pause, Resume, or Force Sync.
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

3.  **Install Services**:
    Run the installer script. It will check connections and set up systemd services.
    ```bash
    ./install.sh
    ```

4.  **(Optional) First Run**:
    If your local folder and cloud folder are vastly different, perform a manual resync first to build the database:
    ```bash
    rclone bisync "remote:" "/local/path" --resync --drive-acknowledge-abuse --verbose
    ```

## ⚙️ Customization

### Ignoring Files (Filters)
Edit `filter-rules.txt` to add patterns you want to exclude from synchronization (e.g., temporary files, heavy build folders).

### Check Status / Logs
To see what CDSync is doing in real-time:
```bash
# View active logs
tail -f cdsync.log
```

```bash
# Check service status
systemctl --user status cdsync-cdsync-watcher.service
```

### ⚡ Performance Tip
To achieve maximum speed and avoid Google API rate limits, it is highly recommended to configure your own **Google Client ID and Secret** in Rclone.
1. Follow the [Rclone instructions](https://rclone.org/drive/#making-your-own-client-id) to create your credentials.
2. Update your configuration: `rclone config` -> Edit remote -> Enter Client ID/Secret.

## 🗑️ Uninstallation

To stop services and remove them from systemd:
```bash
./uninstall.sh
```

## 📄 License

This project is distributed under the MIT License. See the `LICENSE` file for more details.
