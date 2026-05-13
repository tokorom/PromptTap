# PromptTap

English | [日本語](./README.ja.md)

<p align="center">
<img src="./docs/images/logo.png" alt="LOGO" />
</p>

PromptTap is a native macOS application designed to streamline the way you interact with AI agents. It serves as a dedicated workspace to draft, manage, and instantly submit prompts to any application on your Mac.

## Fast Workflow

PromptTap is built for speed. Focus on your thoughts, not the UI:

1. **Invoke**: Double-tap **Command** from any input field in any app to bring up PromptTap.
2. **Draft**: Type your prompt in the clean, distraction-free editor.
3. **Submit**: Press **Cmd + S** to automatically return to your previous app and paste the prompt.

<p align="center">
<img src="./docs/images/demo.gif" alt="DEMO" />
</p>

## Key Features

- **Global Hotkey Accessibility**: Open PromptTap instantly from anywhere with a simple shortcut (default: double-tap **Command**).
- **Direct Submission**: Seamlessly paste your prompts into the application you were just using with a single command.
- **Smart History**: Automatically tracks your past prompts for easy reuse and refinement. Unsaved changes to Templates or Reserves are also captured in history.
- **Templates & Reserves**: Organize frequently used structures. Use the global search to find and apply them instantly.
- **Vim Mode Support**: For power users, a full Vim keybinding mode is available, powered by CodeMirror 6.
- **Native Experience**: A clean, two-pane layout built with SwiftUI that respects macOS design patterns and system preferences.

<p align="center">
<img src="./docs/images/templates.png" alt="TEMPLATES" />
</p>

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `Double Command` | Open PromptTap / Toggle back to target app |
| `Cmd + S` | **Submit**: Return to previous app and paste prompt |
| `Cmd + C` | **Copy**: Copy full prompt to clipboard |
| `Cmd + F` | **Global Search**: Search across Templates, Reserves, and History |
| `Cmd + N` | **Next Item**: Cycle forward through sidebar items |
| `Cmd + P` | **Previous Item**: Cycle backward through sidebar items |
| `Cmd + H` | **History Toggle**: Toggle between latest history and current prompt |
| `Cmd + T` | Open **Template Search** panel |
| `Cmd + R` | Open **Reserve Search** panel |
| `Cmd + E` | Focus the **Editor** |
| `Cmd + L` | Focus the **Sidebar List** |
| `Cmd + ,` | Open **Settings** |

## Installation

### Via Homebrew (Recommended)

```bash
brew tap tokorom/tap
brew install --cask prompttap
```

### Manual Installation

1. Download the latest version `PromptTap-x.x.x.dmg
` from the [Releases](https://github.com/tokorom/PromptTap/releases) page.
2. Open `PromptTap-x.x.x.dmg` and Drag `PromptTap.app` to your `/Applications` folder.
3. Upon first launch, you will be prompted to grant **Accessibility** permissions. This is required for:
   - Detecting the previous application to enable "Submit".
   - Automatically pasting text into other apps.
   - Global hotkey detection.

## Configuration

In the **Settings** (`Cmd + ,`), you can customize:
- **Global Hotkey**: Change the double-tap trigger or set a custom combination.
- **Editor Settings**: Toggle Vim keybindings and Line Wrapping.
- **History**: Set the maximum number of history items to retain.
- **Storage**: Choose a custom folder to store your Templates and Reserves as plain `.txt` files for easy syncing or external editing.

---
*Created by [tokorom](https://github.com/tokorom).*
