//
//  WebPromptEditor.swift
//  PromptTap
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import SwiftUI
import WebKit
import AppKit

final class PasteboardWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command && event.charactersIgnoringModifiers == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let items = pb.pasteboardItems ?? []

        let texts = items.compactMap { item in
            item.string(forType: .string)
        }

        if !texts.isEmpty {
            let joinedText = texts.joined(separator: "\n")
            let script = "window.promptTapEditor?.insertText(\(encodedString(joinedText)));"
            evaluateJavaScript(script)
        }
    }

    private func encodedString(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }
}

enum VimExCommand: String {
    case write = "w"
    case quit = "q"
    case writeQuit = "wq"
    case exit = "x"
    case writeAll = "wa"
    case quitAll = "qa"
    case writeQuitAll = "wqa"
    case forceQuit = "q!"
    case forceQuitAll = "qa!"
    case unknown

    init(from string: String) {
        self = VimExCommand(rawValue: string) ?? .unknown
    }
}

struct WebPromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isSelectionEmpty: Bool

    let usesVimKeyBindings: Bool
    let lineWrapping: Bool
    let shortcuts: [KeyboardShortcutAction: CustomHotkey]
    let focusRequestID: Int
    let onSubmit: () -> Void
    let onCopyAll: () -> Void
    let onSearchGlobal: () -> Void
    let onSearchTemplates: () -> Void
    let onSearchReserves: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "promptTap")

        let webView = PasteboardWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.loadHTMLString(Self.editorHTML, baseURL: Bundle.main.resourceURL)

        // Enable developer tools to help debugging
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        context.coordinator.webView = webView
        context.coordinator.lastKnownText = text
        context.coordinator.lastVimMode = usesVimKeyBindings
        context.coordinator.lastLineWrapping = lineWrapping
        context.coordinator.lastShortcuts = webShortcuts
        context.coordinator.lastFocusRequestID = focusRequestID

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.lastKnownText != text {
            context.coordinator.lastKnownText = text
            context.coordinator.callJavaScriptFunction("setText", argument: text)
        }

        if context.coordinator.lastVimMode != usesVimKeyBindings {
            context.coordinator.lastVimMode = usesVimKeyBindings
            context.coordinator.callJavaScriptFunction("setVim", argument: usesVimKeyBindings)
        }

        if context.coordinator.lastLineWrapping != lineWrapping {
            context.coordinator.lastLineWrapping = lineWrapping
            context.coordinator.callJavaScriptFunction("setLineWrapping", argument: lineWrapping)
        }

        if context.coordinator.lastShortcuts != webShortcuts {
            context.coordinator.lastShortcuts = webShortcuts
            context.coordinator.callJavaScriptFunction("setShortcuts", argument: webShortcuts)
        }

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            if let window = webView.window {
                window.makeFirstResponder(webView)
            }
            let enterInsertMode = focusRequestID > 1000
            context.coordinator.callJavaScript("window.promptTapEditor?.focusEditor(\(enterInsertMode));")
        }
    }
}

extension WebPromptEditor {
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebPromptEditor
        weak var webView: WKWebView?
        var lastKnownText = ""
        var lastVimMode: Bool?
        var lastLineWrapping: Bool?
        var lastShortcuts: [String: WebShortcutDescriptor] = [:]
        var lastFocusRequestID = 0

        init(_ parent: WebPromptEditor) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            callJavaScriptFunction("setText", argument: parent.text)
            callJavaScriptFunction("setVim", argument: parent.usesVimKeyBindings)
            callJavaScriptFunction("setLineWrapping", argument: parent.lineWrapping)
            callJavaScriptFunction("setShortcuts", argument: parent.webShortcuts)
            let enterInsertMode = parent.focusRequestID > 1000
            callJavaScript("window.promptTapEditor?.focusEditor(\(enterInsertMode));")
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            MainActor.assumeIsolated {
                handleScriptMessageBody(message.body)
            }
        }

        private func handleScriptMessageBody(_ messageBody: Any) {
            guard let body = messageBody as? [String: Any],
                  let action = body["action"] as? String else {
                return
            }

            switch action {
            case "textChanged":
                let text = body["text"] as? String ?? ""
                lastKnownText = text
                parent.text = text
            case "selectionChanged":
                parent.isSelectionEmpty = body["isSelectionEmpty"] as? Bool ?? true
            case "submit":
                parent.onSubmit()
            case "searchGlobal":
                parent.onSearchGlobal()
            case "copyAll":
                parent.onCopyAll()
            case "searchTemplates":
                parent.onSearchTemplates()
            case "searchReserves":
                parent.onSearchReserves()
            case "readClipboard":
                let requestId = body["requestId"] as? String ?? ""
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                let script = "window._onClipboardRead(\(jsonString(requestId)), \(jsonString(text)));"
                webView?.evaluateJavaScript(script)
            case "writeClipboard":
                let text = body["text"] as? String ?? ""
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            case "vimExCommand":
                let command = body["command"] as? String ?? ""
                let isDirty = body["isDirty"] as? Bool ?? false
                handleVimExCommand(command: command, isDirty: isDirty)
            case "editorLoadFailed":
                let message = body["message"] as? String ?? "Unknown error"
                print("PromptTap editor fell back to textarea: \(message)")
            default:
                break
            }
        }

        func callJavaScriptFunction(_ name: String, argument: String) {
            guard let encoded = try? JSONEncoder().encode(argument),
                  let json = String(data: encoded, encoding: .utf8) else {
                return
            }

            callJavaScript("window.promptTapEditor?.\(name)(\(json));")
        }

        func callJavaScriptFunction(_ name: String, argument: Bool) {
            let boolString = argument ? "true" : "false"
            callJavaScript("window.promptTapEditor?.\(name)(\(boolString));")
        }

        func callJavaScriptFunction<T: Encodable>(_ name: String, argument: T) {
            guard let encoded = try? JSONEncoder().encode(argument),
                  let json = String(data: encoded, encoding: .utf8) else {
                return
            }

            callJavaScript("window.promptTapEditor?.\(name)(\(json));")
        }

        func callJavaScript(_ script: String) {
            webView?.evaluateJavaScript(script)
        }

        private func handleVimExCommand(command: String, isDirty: Bool) {
            let exCommand = VimExCommand(from: command)
            print("Vim Ex Command received: \(exCommand)")

            switch exCommand {
            case .write, .writeAll:
                parent.onSubmit()
            case .exit, .quit, .quitAll, .forceQuit, .forceQuitAll:
                parent.onClose()
            case .writeQuit, .writeQuitAll:
                parent.onSubmit()
            case .unknown:
                print("Warning: Unknown Vim Ex command received: \(command)")
            }
        }

        private func jsonString(_ string: String) -> String {
            guard let data = try? JSONEncoder().encode(string),
                  let json = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return json
        }
    }
}

private extension WebPromptEditor {
    var webShortcuts: [String: WebShortcutDescriptor] {
        [
            "submit": shortcutDescriptor(for: .submit),
            "copyAll": shortcutDescriptor(for: .copy),
            "searchGlobal": shortcutDescriptor(for: .globalSearch),
            "searchTemplates": shortcutDescriptor(for: .templateSearch),
            "searchReserves": shortcutDescriptor(for: .reserveSearch)
        ]
    }

    func shortcutDescriptor(for action: KeyboardShortcutAction) -> WebShortcutDescriptor {
        (shortcuts[action] ?? action.defaultHotkey).webShortcutDescriptor
    }

    static let editorHTML = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root {
          color-scheme: light dark;
          font: -apple-system-body;
          --editor-font: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
        }

        html, body, #editor {
          height: 100%;
          width: 100%;
          margin: 0;
          padding: 0;
          box-sizing: border-box;
        }

        body {
          background: Canvas;
          color: CanvasText;
          overflow: hidden;
        }

        .cm-editor {
          height: 100%;
          width: 100%;
          font-family: var(--editor-font);
          font-size: 14px;
        }

        .cm-scroller {
          line-height: 1.55;
        }

        .cm-editor.prompttap-lineWrapping .cm-scroller {
          overflow-x: hidden !important;
        }

        .cm-content.cm-lineWrapping {
          word-break: break-all;
          overflow-wrap: anywhere;
          line-break: anywhere;
        }

        .cm-content.cm-lineWrapping .cm-line {
          word-break: break-all;
          overflow-wrap: anywhere;
          line-break: anywhere;
        }

        .cm-vim-panel {
          border-top: 1px solid color-mix(in srgb, CanvasText 12%, transparent);
          color: GrayText;
          font-family: var(--editor-font);
          font-size: 12px;
          padding: 3px 8px;
        }

        textarea.fallback-editor {
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          border: 0;
          outline: 0;
          resize: none;
          padding: 14px;
          background: Canvas;
          color: CanvasText;
          font-family: var(--editor-font);
          font-size: 14px;
          line-height: 1.55;
        }
      </style>
    </head>
    <body>
      <div id="editor"></div>
      <script src="PromptTapEditorBundle.js"></script>
      <script>
        const bridge = window.webkit?.messageHandlers?.promptTap;
        const post = (message) => bridge?.postMessage(message);

        let view = null;
        let textarea = null;
        let vimCompartment = null;
        let vimExtensionFactory = null;
        let lineWrappingCompartment = null;
        let lineWrappingExtension = [];

        let isInitialized = false;
        let pendingText = "";
        let pendingVim = false;
        let pendingLineWrapping = false;
        let pendingFocus = false;
        let pendingVimInsert = false;
        let appliedVim = null;
        let appliedLineWrapping = null;
        let isApplyingState = false;
        let defaultShortcuts = {
          submit: { key: "s", command: true, shift: false, option: false, control: false },
          copyAll: { key: "c", command: true, shift: false, option: false, control: false },
          searchGlobal: { key: "f", command: true, shift: false, option: false, control: false },
          searchTemplates: { key: "t", command: true, shift: false, option: false, control: false },
          searchReserves: { key: "r", command: true, shift: false, option: false, control: false },
        };
        let pendingShortcuts = defaultShortcuts;

        const hasSelection = () => {
          if (view) {
            return view.state.selection.ranges.some((range) => !range.empty);
          }
          if (textarea) {
            return textarea.selectionStart !== textarea.selectionEnd;
          }
          return false;
        };

        const notifySelection = () => {
          post({ action: "selectionChanged", isSelectionEmpty: !hasSelection() });
        };

        let lastSavedContent = "";

        const notifyText = (value) => {
          if (!isInitialized && value === "") return;
          post({ action: "textChanged", text: value });
        };

        const installCommandShortcuts = (target) => {
          target.addEventListener("keydown", (event) => {
            for (const [action, shortcut] of Object.entries(pendingShortcuts)) {
              if (!matchesShortcut(event, shortcut)) continue;
              if (action === "copyAll" && hasSelection()) return;
              event.preventDefault();
              post({ action });
              return;
            }
          }, true); // Use capture phase to catch it early
        };

        const matchesShortcut = (event, shortcut) => {
          if (!shortcut) return false;
          return event.key.toLowerCase() === shortcut.key &&
            event.metaKey === shortcut.command &&
            event.shiftKey === shortcut.shift &&
            event.altKey === shortcut.option &&
            event.ctrlKey === shortcut.control;
        };

        const vimExtension = () => vimExtensionFactory({ status: true });

        const applyState = () => {
          if (view) {
            const transaction = {};
            let needsDispatch = false;

            if (view.state.doc.toString() !== pendingText) {
              transaction.changes = { from: 0, to: view.state.doc.length, insert: pendingText };
              needsDispatch = true;
            }

            const effects = [];
            if (vimCompartment && vimExtensionFactory && appliedVim !== pendingVim) {
              effects.push(vimCompartment.reconfigure(pendingVim ? vimExtension() : []));
              appliedVim = pendingVim;
            }
            if (lineWrappingCompartment && appliedLineWrapping !== pendingLineWrapping) {
              effects.push(lineWrappingCompartment.reconfigure(pendingLineWrapping ? lineWrappingExtension : []));
              appliedLineWrapping = pendingLineWrapping;
            }

            if (effects.length > 0) {
              transaction.effects = effects;
              needsDispatch = true;
            }

            if (needsDispatch) {
              isApplyingState = true;
              try {
                view.dispatch(transaction);
              } finally {
                isApplyingState = false;
              }
            }

            view.dom.classList.toggle("prompttap-lineWrapping", pendingLineWrapping);
            if (pendingFocus) {
              view.focus();
              pendingFocus = false;
              if (pendingVimInsert && appliedVim) {
                setTimeout(() => {
                  const cm = view.cm;
                  if (cm && cm.handleKey) {
                    cm.handleKey("i");
                  } else {
                    const target = view.contentDOM || view.dom;
                    if (target) {
                      target.focus();
                      target.dispatchEvent(new KeyboardEvent("keydown", {
                        key: "i",
                        keyCode: 73,
                        code: "KeyI",
                        while: 73,
                        bubbles: true,
                        cancelable: true
                      }));
                    }
                  }
                }, 600);
                pendingVimInsert = false;
              }
            }
          } else if (textarea) {
            if (textarea.value !== pendingText) {
              textarea.value = pendingText;
            }
            if (textarea.style.whiteSpace !== (pendingLineWrapping ? "pre-wrap" : "pre")) {
                textarea.style.whiteSpace = pendingLineWrapping ? "pre-wrap" : "pre";
                textarea.style.overflowX = pendingLineWrapping ? "hidden" : "auto";
            }
            if (pendingFocus) {
              textarea.focus();
              pendingFocus = false;
            }
          }
        };

        const setupCodeMirror = () => {
          const modules = window.PromptTapEditorBundle;
          if (!modules) {
            throw new Error("PromptTapEditorBundle.js was not loaded");
          }

          // System Clipboard Adapter (Native Bridge)
          window._clipboardCallbacks = {};
          window._onClipboardRead = (requestId, text) => {
            if (window._clipboardCallbacks[requestId]) {
              window._clipboardCallbacks[requestId](text);
              delete window._clipboardCallbacks[requestId];
            }
          };

          window.SystemClipboard = {
            async readText() {
              return new Promise((resolve) => {
                const requestId = Math.random().toString(36).substring(7);
                window._clipboardCallbacks[requestId] = resolve;
                window.webkit.messageHandlers.promptTap.postMessage({
                  action: "readClipboard",
                  requestId: requestId
                });
                // Fallback timeout
                setTimeout(() => {
                  if (window._clipboardCallbacks[requestId]) {
                    window._clipboardCallbacks[requestId](null);
                    delete window._clipboardCallbacks[requestId];
                  }
                }, 1000);
              });
            },
            async writeText(text) {
              window.webkit.messageHandlers.promptTap.postMessage({
                action: "writeClipboard",
                text: text
              });
              return true;
            }
          };
          window.vimClipboard = "unnamedplus";

          const {
            EditorState,
            Compartment,
            EditorView,
            keymap,
            lineNumbers,
            highlightActiveLine,
            placeholder,
            drawSelection,
            defaultKeymap,
            history,
            historyKeymap,
            indentWithTab,
            markdown,
            vim
          } = modules;

          const Vim = vim.Vim;
          if (Vim && Vim.defineEx) {
            const sendEx = (cmd) => {
              window.webkit.messageHandlers.promptTap.postMessage({
                action: "vimExCommand",
                command: cmd,
                isDirty: window.promptTapEditor?.isDirty() || false
              });
            };

            Vim.defineEx("write", "w", () => sendEx("w"));
            Vim.defineEx("quit", "q", (cm, params) => sendEx(params.commandName.endsWith("!") ? "q!" : "q"));
            Vim.defineEx("wq", "", () => sendEx("wq"));
            Vim.defineEx("exit", "x", () => sendEx("x"));
            Vim.defineEx("wall", "wa", () => sendEx("wa"));
            Vim.defineEx("qall", "qa", (cm, params) => sendEx(params.commandName.endsWith("!") ? "qa!" : "qa"));
            Vim.defineEx("wqall", "wqa", () => sendEx("wqa"));
          }

          vimCompartment = new Compartment();
          vimExtensionFactory = vim;
          lineWrappingCompartment = new Compartment();
          lineWrappingExtension = EditorView.lineWrapping;

          const updateListener = EditorView.updateListener.of((update) => {
            if (update.docChanged) {
              const currentText = update.state.doc.toString();
              pendingText = currentText;
              if (!isApplyingState) {
                notifyText(currentText);
              }
            }
            if (update.selectionSet || update.docChanged || update.focusChanged) {
              notifySelection();
            }
          });

          const theme = EditorView.theme({
            "&": {
              backgroundColor: "Canvas",
              color: "CanvasText"
            },
            ".cm-content": {
              padding: "14px 12px",
              caretColor: "CanvasText"
            },
            ".cm-gutters": {
              backgroundColor: "Canvas",
              color: "GrayText",
              borderRightColor: "color-mix(in srgb, CanvasText 12%, transparent)"
            },
            ".cm-activeLine, .cm-activeLineGutter": {
              backgroundColor: "color-mix(in srgb, Highlight 12%, transparent)"
            },
            ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
              backgroundColor: "color-mix(in srgb, Highlight 35%, transparent)"
            },
            "&.cm-focused": {
              outline: "none"
            },
            ".cm-fat-cursor": {
              backgroundColor: "CanvasText !important",
              color: "Canvas !important"
            }
          });

          const state = EditorState.create({
            doc: pendingText,
            extensions: [
              vimCompartment.of(pendingVim ? vimExtension() : []),
              lineWrappingCompartment.of(pendingLineWrapping ? lineWrappingExtension : []),
              lineNumbers(),
              history(),
              markdown(),
              drawSelection(),
              highlightActiveLine(),
              placeholder("Write a prompt..."),
              theme,
              updateListener,
              keymap.of([indentWithTab, ...defaultKeymap, ...historyKeymap]),
            ]
          });

          view = new EditorView({
            state,
            parent: document.getElementById("editor")
          });

          appliedVim = pendingVim;
          appliedLineWrapping = pendingLineWrapping;
          installCommandShortcuts(view.dom);
          applyState();
        };

        const setupFallbackEditor = () => {
          textarea = document.createElement("textarea");
          textarea.className = "fallback-editor";
          textarea.spellcheck = false;
          textarea.placeholder = "Write a prompt...";
          document.getElementById("editor").replaceChildren(textarea);

          textarea.addEventListener("input", () => notifyText(textarea.value));
          textarea.addEventListener("select", notifySelection);
          textarea.addEventListener("keyup", notifySelection);
          textarea.addEventListener("mouseup", notifySelection);
          installCommandShortcuts(textarea);
          applyState();
        };

        window.promptTapEditor = {
          setText(value) {
            isInitialized = true;
            pendingText = value;
            lastSavedContent = value;
            applyState();
          },
          setVim(enabled) {
            if (view) {
              pendingText = view.state.doc.toString();
            } else if (textarea) {
              pendingText = textarea.value;
            }
            pendingVim = enabled;
            applyState();
          },
          setLineWrapping(enabled) {
            if (view) {
              pendingText = view.state.doc.toString();
            } else if (textarea) {
              pendingText = textarea.value;
            }
            pendingLineWrapping = enabled;
            applyState();
          },
          setShortcuts(shortcuts) {
            pendingShortcuts = { ...defaultShortcuts, ...shortcuts };
          },
          insertText(value) {
            if (view) {
              const transaction = view.state.replaceSelection(value);
              view.dispatch(transaction);
            } else if (textarea) {
              const start = textarea.selectionStart;
              const end = textarea.selectionEnd;
              const current = textarea.value;
              textarea.value = current.substring(0, start) + value + current.substring(end);
              textarea.selectionStart = textarea.selectionEnd = start + value.length;
              notifyText(textarea.value);
            }
          },
          focusEditor(enterVimInsertMode) {
            pendingFocus = true;
            if (enterVimInsertMode) {
              pendingVimInsert = true;
            }
            applyState();
            notifySelection();
          },
          isDirty() {
            const current = view ? view.state.doc.toString() : (textarea ? textarea.value : "");
            return current !== lastSavedContent;
          },
          markClean() {
            lastSavedContent = view ? view.state.doc.toString() : (textarea ? textarea.value : "");
          },
          showVimMessage(message, isError) {
            const cm = view?.cm;
            if (cm && cm.openNotification) {
              const div = document.createElement("div");
              if (isError) div.style.color = "red";
              div.textContent = message;
              cm.openNotification(div, { bottom: true, duration: 5000 });
            } else {
              console.log("Vim Message:", message);
            }
          }
        };

        try {
          setupCodeMirror();
        } catch (error) {
          post({ action: "editorLoadFailed", message: error?.message ?? String(error) });
          setupFallbackEditor();
        }

        setTimeout(() => {
          window.promptTapEditor.focusEditor(false);
        }, 300);
      </script>
    </body>
    </html>
    """
}
