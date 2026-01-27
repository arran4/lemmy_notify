# Lemmy Notify

**Lemmy Notify** is a desktop application that sits in your system tray and monitors your Lemmy account for new posts and private messages. It acts as a lightweight indicator, allowing you to stay updated without constantly checking your browser.

> **Note:** Currently, this functions primarily as a system tray indicator.

## Features

*   **Cross-Platform Support**: Works on Windows, Linux, and macOS.
*   **System Tray Integration**:
    *   Displays status icons (No updates, New Messages, New Posts).
    *   Tooltip with quick summary (New Posts/Messages count).
    *   Context menu for quick actions (Refresh, Settings, Show App, Quit).
*   **Notifications**:
    *   Detects new private messages.
    *   Detects new posts in your subscribed communities (checking for unread posts or posts with unread comments).
*   **Secure**: Uses secure storage for saving your password.
*   **Configurable**:
    *   Set your Lemmy instance URL.
    *   Adjust polling interval (default: 5 minutes).
    *   Option to start minimized to the system tray.
*   **Interactive UI**:
    *   Main window displays clickable links to new posts and your instance.
    *   Shows delta counts for updates.

## Screenshots

### Main Interface
![Main App Window](docs/img_1.png)

### System Tray & Menu
![Tray Icon and Menu](docs/img.png)

### Settings
![Settings](docs/img_2.png)

### Status Icons

| Icon | Meaning |
| :---: | :--- |
| ![No Updates](images/tray_icon.png) | **No Updates**: You are all caught up. |
| ![New Messages](images/tray_icon_new_messages.png) | **New Messages**: You have unread private messages. |
| ![New Posts](images/tray_icon_new_posts.png) | **New Posts**: There are new posts or comments to view. |

## Installation

### Downloads
Check the [Releases page](https://github.com/arran4/lemmy_notify/releases) for the latest binaries for your platform.

### Building from Source

If you prefer to build the application yourself, follow these steps.

#### Prerequisites

1.  **Flutter SDK**: Ensure you have Flutter installed (SDK version >=3.1.5 <4.0.0). [Install Flutter](https://docs.flutter.dev/get-started/install).
2.  **Git**: To clone the repository.

#### Linux Requirements
If you are building on Linux, you will need the following development packages:

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libappindicator3-dev libsecret-1-dev libjsoncpp-dev libnotify-dev
```

#### Build Steps

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/arran4/lemmy_notify.git
    cd lemmy_notify
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Run the app:**
    ```bash
    # For Windows
    flutter run -d windows

    # For Linux
    flutter run -d linux

    # For macOS
    flutter run -d macos
    ```

4.  **Build for release:**
    ```bash
    flutter build windows
    flutter build linux
    flutter build macos
    ```

## Configuration

1.  Launch the application.
2.  Open **Settings** (either from the window or the system tray context menu).
3.  Enter your **Lemmy Server URL** (e.g., `https://lemmy.world`).
4.  Enter your **Username** and **Password**.
5.  Set the **Timer Interval** (in minutes) for how often to check for updates.
6.  Click **Save**.

The status will update to "Configured" and then "Updated" once it successfully connects and fetches data.

## Development

The main application logic is contained within `lib/main.dart`. It utilizes the `lemmy_api_client` (v3) for API interaction and `tray_manager`/`window_manager` for desktop integration.
