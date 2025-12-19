# CDSync: Cloud Drive Synchronization for Linux

CDSync is a lightweight, automated synchronization solution for Linux users who require a local physical copy of their cloud data. Built upon the robust Rclone engine and integrated with systemd and inotify, CDSync provides a background daemon experience similar to official cloud clients on other platforms.

---

## Overview

Unlike streaming-only solutions or manual script execution, CDSync ensures that your cloud data is permanently available locally, enabling offline access and high-performance file management.

*   **Offline Availability:** Files are stored physically on your local storage, allowing for uninterrupted workflow without internet access.
*   **Real-time Synchronization:** Utilizes `inotify` to detect local file changes and perform targeted uploads instantly.
*   **Optimized Resource Management:** Designed with a "Skip-if-Busy" strategy to prevent system load spikes during mass file operations, deferring complex tasks to periodic cycles.
*   **System Tray Integration:** Provides a graphical user interface for status monitoring, activity logging, and configuration management.

---

## Core Features

### Hybrid Synchronization Architecture
CDSync employs a two-tier synchronization strategy:
1.  **Event-Driven Smart Sync:** Immediate synchronization of individual file changes to maintain real-time parity.
2.  **Periodic Verification:** Regularly scheduled bidirectional synchronization (via `rclone bisync`) to ensure structural consistency and fetch remote changes.

### Intelligent Conflict Management
Includes a configurable "Force Sync Newer" mechanism. This is particularly valuable for **Google Drive** environments, as Google Drive allows multiple files with identical names to coexist in the same directory. Enabling this feature ensures that the most recent version of a file takes precedence, maintaining a clean local and remote file structure.

### Remote Deduplication Management
Direct UI access to deduplication tools, allowing users to resolve remote naming conflicts either by renaming duplicates or retaining only the latest version.

---

## Installation and Setup

### 1. Requirements
Ensure you have `rclone` (v1.60+), `inotify-tools`, and Python GTK libraries installed on your system.

### 2. Configuration
Clone the repository and initialize the configuration:
```bash
git clone https://github.com/muller-front/cdsync.git
cd cdsync
cp config.env.example config.env
```
Edit `config.env` to specify your `RCLONE_REMOTE` and `LOCAL_SYNC_DIR`.

### 3. Deployment
Run the installation script to set up the systemd user services:
```bash
./install.sh
```

---

## Usage and Configuration

### System Tray Interface
*   **Service Status:** Toggle the synchronization daemon between active and inactive states.
*   **Activity Monitor:** Review recent synchronization events with specific indicators for file creations, updates, and deletions.
*   **Manual Synchronization:** Trigger an immediate synchronization cycle outside of the standard schedule.

### Advanced Settings
*   **Polling Interval:** Configure the frequency of remote change checks.
*   **Notification Management:** Adjust notification verbosity between "All Events", "Errors Only", or "Disabled".
*   **Maintenance Tools:** Access the "Force Resync" option to rebuild the local synchronization database in case of state corruption.

---

## Technical Notes

*   **Platform Support:** CDSync has been extensively tested with **Google Drive**. While it uses standard Rclone protocols, behavior with other cloud providers may vary.
*   **Anti-Loop Mechanism:** Implements a "Smart Ignore List" that parses synchronization logs to distinguish between user-initiated changes and system-initiated downloads, preventing infinite loop conditions.

---

## Changelog

### v1.7
*   Implementation of Remote Deduplication management.
*   Security hardening of configuration parsing logic.
*   Optimization of shallow sync performance (Skip-if-Busy strategy).
*   UI refinement and removal of redundant menu items.

### v1.6
*   Migration to Smart Ignore List architecture for loop prevention.
*   Implementation of notification level controls.
*   Integration of directory-level event handling for structural parity.

---

## License
Distributed under the MIT License. See `LICENSE` for details.
