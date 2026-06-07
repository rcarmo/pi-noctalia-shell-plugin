import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi: null

  property var messages: []
  property bool isGenerating: false
  property string currentResponse: ""
  property string currentThinking: ""
  property var currentToolEvents: []
  property bool thinkingPanelExpanded: true
  property bool toolsPanelExpanded: true
  property bool panelPinned: pluginApi?.pluginSettings?.panelPinned ?? false
  property var lastPanelScreen: null
  property var standaloneScreen: null
  property string errorMessage: ""
  property bool backendReady: false
  property string backendStatus: ""
  property string backendModel: ""
  property string backendCwd: ""
  property var backendModelInfo: null
  property var backendContextUsage: null
  property string backendThinkingLevel: ""
  property bool startingBackend: false
  property var availableModels: []
  property var availableCommands: []
  property bool modelsLoading: false
  property bool commandsLoading: false
  property bool modelChangeInProgress: false
  property int backendRetryAttempts: 0
  property bool suppressNextEventsExit: false

  property var pendingCommandCallback: null
  property string pendingCommandName: ""

  readonly property var aiSettings: pluginApi?.pluginSettings?.ai ?? pluginApi?.manifest?.metadata?.defaultSettings?.ai ?? ({})
  readonly property int maxHistoryLength: pluginApi?.pluginSettings?.maxHistoryLength ?? pluginApi?.manifest?.metadata?.defaultSettings?.maxHistoryLength ?? 100
  readonly property string piCommand: (aiSettings.piCommand ?? "pi").trim() || "pi"
  readonly property string model: (aiSettings.model ?? "").trim()
  readonly property string thinkingLevel: (aiSettings.thinkingLevel ?? "medium").trim() || "medium"
  readonly property string panelPosition: (pluginApi?.pluginSettings?.panelPosition ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelPosition ?? "right").trim() || "right"
  readonly property string toolsMode: (aiSettings.toolsMode ?? "none").trim() || "none"
  readonly property bool persistentSession: aiSettings.persistentSession ?? false
  readonly property string sessionName: (aiSettings.sessionName ?? "Noctalia Pi Assistant").trim() || "Noctalia Pi Assistant"

  readonly property string pluginDir: pluginApi?.pluginDir ?? ""
  readonly property string helperPath: pluginDir + "/pi-rpc-bridge.py"
  readonly property string cacheDir: typeof Settings !== "undefined" && Settings.cacheDir ? Settings.cacheDir + "plugins/pi-assistant-panel/" : "/tmp/"
  readonly property string socketPath: cacheDir + "backend.sock"
  readonly property string resolvedModel: backendModel || model
  readonly property var currentPanelScreen: pluginApi?.panelOpenScreen ?? null
  readonly property string modelStatusLine: formatModelStatusLine(backendCwd, backendModelInfo, backendThinkingLevel, backendContextUsage, backendReady, backendStatus)

  function tr(key, params) {
    return pluginApi?.tr(key, params);
  }

  function modelKey(provider, modelId) {
    const p = (provider || "").trim();
    const id = (modelId || "").trim();
    return p && id ? (p + "/" + id) : "";
  }

  function stringifyModel(value) {
    if (!value)
      return "";
    if (typeof value === "string")
      return value.trim();
    if (typeof value === "object")
      return modelKey(value.provider, value.id);
    return "";
  }

  function formatTokenCount(count) {
    const value = Number(count || 0);
    if (!isFinite(value) || value <= 0)
      return "0";
    if (value < 1000)
      return String(Math.round(value));
    if (value < 10000)
      return (value / 1000).toFixed(1) + "k";
    if (value < 1000000)
      return Math.round(value / 1000) + "k";
    if (value < 10000000)
      return (value / 1000000).toFixed(1) + "M";
    return Math.round(value / 1000000) + "M";
  }

  function formatCwd(value) {
    const source = (value || "").trim();
    if (!source)
      return "";
    const home = Quickshell.env("HOME") || "";
    let next = source;
    if (home && next.indexOf(home) === 0)
      next = "~" + next.slice(home.length);
    if (next.length > 28)
      next = "…" + next.slice(next.length - 27);
    return next;
  }

  function formatContextIndicator(contextUsage, modelInfo) {
    const usage = contextUsage || {};
    const contextWindow = Number(usage?.contextWindow ?? modelInfo?.contextWindow ?? 0);
    if (!isFinite(contextWindow) || contextWindow <= 0)
      return "?/0";
    const percent = usage?.percent;
    if (percent === null || percent === undefined || !isFinite(Number(percent)))
      return "?/" + formatTokenCount(contextWindow);
    return Number(percent).toFixed(1) + "%/" + formatTokenCount(contextWindow);
  }

  function formatModelStatusLine(cwd, modelInfo, activeThinkingLevel, contextUsage, isReady, fallbackStatus) {
    if (!isReady)
      return fallbackStatus || (tr("chat.backendNotReady") || "Backend not ready");
    const info = modelInfo || {};
    const modelName = info?.id || stringifyModel(info) || resolvedModel || "no-model";
    const parts = [];
    const shortCwd = formatCwd(cwd);
    if (shortCwd)
      parts.push(shortCwd);
    parts.push(formatContextIndicator(contextUsage, info), modelName, activeThinkingLevel || "off");
    return parts.join(" • ");
  }

  function rebuildAvailableModels(rawModels) {
    const next = [];
    for (const modelInfo of (rawModels || [])) {
      const key = modelKey(modelInfo?.provider, modelInfo?.id);
      if (!key)
        continue;
      const detail = [];
      if (modelInfo?.reasoning)
        detail.push("reasoning");
      if (modelInfo?.contextWindow)
        detail.push(Math.round(modelInfo.contextWindow / 1000) + "k ctx");
      next.push({
        "key": key,
        "name": detail.length > 0 ? (key + " — " + detail.join(" · ")) : key,
        "provider": modelInfo?.provider || "",
        "id": modelInfo?.id || "",
        "contextWindow": modelInfo?.contextWindow || 0,
        "reasoning": !!modelInfo?.reasoning,
        "cost": modelInfo?.cost || null
      });
    }
    const current = stringifyModel(resolvedModel);
    if (current && !next.some(function (entry) {
      return entry.key === current;
    })) {
      const slashIndex = current.indexOf("/");
      next.unshift({
        "key": current,
        "name": current,
        "provider": slashIndex > 0 ? current.slice(0, slashIndex) : "",
        "id": slashIndex > 0 ? current.slice(slashIndex + 1) : current,
        "contextWindow": 0,
        "reasoning": false,
        "cost": null
      });
    }
    availableModels = next;
  }

  function refreshAvailableModels() {
    if (!backendReady) {
      modelsLoading = false;
      return false;
    }
    if (commandProcess.running) {
      modelRefreshTimer.restart();
      return false;
    }
    modelsLoading = true;
    const started = sendCommand({ "command": "get_available_models" }, function (reply) {
      modelsLoading = false;
      if (!reply?.ok) {
        Logger.w("[pi-assistant-panel] failed to fetch models:", reply?.error || "unknown error");
        return;
      }
      rebuildAvailableModels(reply?.response?.data?.models || []);
    });
    if (!started)
      modelsLoading = false;
    return started;
  }

  function builtinSlashCommands() {
    return [
      { "key": "/new", "name": "/new", "description": "Start a new session", "source": "builtin" },
      { "key": "/compact", "name": "/compact", "description": "Compact the current session context", "source": "builtin" },
      { "key": "/session", "name": "/session", "description": "Show session info and context usage", "source": "builtin" },
      { "key": "/name", "name": "/name", "description": "Set the session display name", "source": "builtin" },
      { "key": "/thinking", "name": "/thinking", "description": "Set thinking level: off|minimal|low|medium|high|xhigh", "source": "builtin" },
      { "key": "/think", "name": "/think", "description": "Alias for /thinking", "source": "builtin" },
      { "key": "/model", "name": "/model", "description": "Use the model dropdown in the panel header", "source": "builtin" },
      { "key": "/clear", "name": "/clear", "description": "Clear visible chat history in the panel", "source": "builtin" }
    ];
  }

  function rebuildAvailableCommands(rawCommands) {
    const next = builtinSlashCommands();
    for (const commandInfo of (rawCommands || [])) {
      const name = (commandInfo?.name || "").trim();
      if (!name)
        continue;
      const key = "/" + name;
      if (next.some(function (entry) {
        return entry.key === key;
      }))
        continue;
      next.push({
        "key": key,
        "name": key,
        "description": (commandInfo?.description || "").trim(),
        "source": (commandInfo?.source || "").trim()
      });
    }
    availableCommands = next;
  }

  function refreshAvailableCommands() {
    if (!backendReady) {
      commandsLoading = false;
      return false;
    }
    if (commandProcess.running) {
      commandRefreshTimer.restart();
      return false;
    }
    commandsLoading = true;
    const started = sendCommand({ "command": "get_commands" }, function (reply) {
      commandsLoading = false;
      if (!reply?.ok) {
        Logger.w("[pi-assistant-panel] failed to fetch commands:", reply?.error || "unknown error");
        return;
      }
      rebuildAvailableCommands(reply?.response?.data?.commands || []);
    });
    if (!started)
      commandsLoading = false;
    return started;
  }

  function persistSelectedModel(selectedModel) {
    const nextModel = stringifyModel(selectedModel);
    if (!pluginApi)
      return;
    if (!pluginApi.pluginSettings.ai)
      pluginApi.pluginSettings.ai = {};
    if ((pluginApi.pluginSettings.ai.model || "") === nextModel)
      return;
    pluginApi.pluginSettings.ai.model = nextModel;
    pluginApi.saveSettings();
  }

  function persistThinkingLevel(selectedThinkingLevel) {
    const nextLevel = (selectedThinkingLevel || "").trim() || "medium";
    if (!pluginApi)
      return;
    if (!pluginApi.pluginSettings.ai)
      pluginApi.pluginSettings.ai = {};
    if ((pluginApi.pluginSettings.ai.thinkingLevel || "") === nextLevel)
      return;
    pluginApi.pluginSettings.ai.thinkingLevel = nextLevel;
    pluginApi.saveSettings();
  }

  function persistPanelPinned(pinned) {
    if (!pluginApi)
      return;
    if ((pluginApi.pluginSettings.panelPinned ?? false) === !!pinned)
      return;
    pluginApi.pluginSettings.panelPinned = !!pinned;
    pluginApi.saveSettings();
  }

  function setPanelPinned(pinned, persist, preferredScreen) {
    const nextPinned = !!pinned;
    const targetScreen = preferredScreen || currentPanelScreen || lastPanelScreen;
    if (targetScreen)
      lastPanelScreen = targetScreen;
    if (panelPinned === nextPinned) {
      if (nextPinned && !standaloneScreen)
        openStandaloneWindow(targetScreen);
      return;
    }
    panelPinned = nextPinned;
    if (persist !== false)
      persistPanelPinned(panelPinned);
    if (panelPinned) {
      const screen = targetScreen;
      if (currentPanelScreen && pluginApi)
        pluginApi.closePanel(currentPanelScreen);
      if (screen)
        openStandaloneWindow(screen);
    } else {
      closeStandaloneWindow();
      if (lastPanelScreen && pluginApi)
        pluginApi.openPanel(lastPanelScreen);
    }
  }

  function applySavedPanelSettings() {
    setPanelPinned(pluginApi?.pluginSettings?.panelPinned ?? false, false);
  }

  function togglePanelPinned(screen) {
    setPanelPinned(!panelPinned, true, screen);
  }

  function persistPanelPosition(position) {
    const nextPosition = (position || "").trim();
    if (!pluginApi || !nextPosition)
      return;
    if ((pluginApi.pluginSettings.panelPosition || "") === nextPosition)
      return;
    pluginApi.pluginSettings.panelPosition = nextPosition;
    pluginApi.saveSettings();
  }

  function openStandaloneWindow(screen) {
    standaloneScreen = screen || lastPanelScreen || null;
    if (standaloneScreen)
      lastPanelScreen = standaloneScreen;
  }

  function closeStandaloneWindow() {
    standaloneScreen = null;
  }

  function openPreferredUI(screen, buttonItem) {
    if (screen)
      lastPanelScreen = screen;
    if (panelPinned) {
      openStandaloneWindow(screen);
      if (pluginApi?.panelOpenScreen)
        pluginApi.closePanel(pluginApi.panelOpenScreen);
      return true;
    }
    return pluginApi ? pluginApi.openPanel(screen, buttonItem) : false;
  }

  function togglePreferredUI(screen, buttonItem) {
    if (screen)
      lastPanelScreen = screen;
    if (panelPinned) {
      if (standaloneScreen)
        closeStandaloneWindow();
      else
        openStandaloneWindow(screen);
      if (pluginApi?.panelOpenScreen)
        pluginApi.closePanel(pluginApi.panelOpenScreen);
      return true;
    }
    return pluginApi ? pluginApi.togglePanel(screen, buttonItem) : false;
  }

  function closePreferredUI(screen) {
    closeStandaloneWindow();
    return pluginApi ? pluginApi.closePanel(screen || lastPanelScreen) : false;
  }

  function reopenPinnedPanel() {
    if (!panelPinned || !lastPanelScreen)
      return;
    openStandaloneWindow(lastPanelScreen);
  }

  function setActiveThinkingLevel(level) {
    const nextLevel = (level || "").trim().toLowerCase();
    const allowedLevels = ["off", "minimal", "low", "medium", "high", "xhigh"];
    if (!nextLevel || allowedLevels.indexOf(nextLevel) < 0)
      return false;
    if (nextLevel === (backendThinkingLevel || thinkingLevel || "medium"))
      return false;
    if (commandProcess.running)
      return false;
    errorMessage = "";
    return sendCommand({ "command": "set_thinking_level", "level": nextLevel }, function (reply) {
      if (!reply?.ok) {
        errorMessage = reply?.error || tr("errors.requestFailed") || "Request failed.";
        return;
      }
      backendThinkingLevel = nextLevel;
      persistThinkingLevel(nextLevel);
      stateRefreshTimer.restart();
    });
  }

  function setActiveModel(modelName) {
    const nextModel = stringifyModel(modelName);
    if (!nextModel || nextModel === stringifyModel(resolvedModel) || isGenerating || modelChangeInProgress)
      return false;
    const slashIndex = nextModel.indexOf("/");
    if (slashIndex <= 0 || slashIndex === nextModel.length - 1)
      return false;
    if (commandProcess.running)
      return false;
    errorMessage = "";
    modelChangeInProgress = true;
    return sendCommand({
      "command": "set_model",
      "provider": nextModel.slice(0, slashIndex),
      "modelId": nextModel.slice(slashIndex + 1)
    }, function (reply) {
      modelChangeInProgress = false;
      if (!reply?.ok) {
        errorMessage = reply?.error || tr("errors.requestFailed") || "Request failed.";
        return;
      }
      const data = reply?.response?.data || {};
      backendModelInfo = data;
      backendModel = modelKey(data?.provider, data?.id) || nextModel;
      persistSelectedModel(backendModel);
      stateRefreshTimer.restart();
      modelRefreshTimer.restart();
    });
  }

  function ensureCacheDir() {
    if (cacheDir)
      Quickshell.execDetached(["mkdir", "-p", cacheDir]);
  }

  function helperCommandArgs(mode, payload, waitSeconds) {
    const args = ["python3", helperPath, mode, "--socket", socketPath];
    if (mode === "command") {
      args.push("--json");
      args.push(JSON.stringify(payload || {}));
      args.push("--wait");
      args.push(String(waitSeconds ?? 5));
    } else if (mode === "subscribe") {
      args.push("--wait");
      args.push(String(waitSeconds ?? 10));
    } else if (mode === "daemon") {
      args.push("--pi-command");
      args.push(piCommand);
      if (model) {
        args.push("--model");
        args.push(model);
      }
      if (thinkingLevel) {
        args.push("--thinking");
        args.push(thinkingLevel);
      }
      args.push("--tools-mode");
      args.push(toolsMode);
      if (persistentSession)
        args.push("--persistent-session");
      if (sessionName) {
        args.push("--session-name");
        args.push(sessionName);
      }
    }
    return args;
  }

  function startBackend() {
    if (!helperPath || !pluginDir)
      return;
    if (startingBackend)
      return;
    ensureCacheDir();
    startingBackend = true;
    backendReady = false;
    backendCwd = "";
    backendModelInfo = null;
    backendContextUsage = null;
    modelsLoading = false;
    commandsLoading = false;
    modelChangeInProgress = false;
    availableModels = [];
    availableCommands = builtinSlashCommands();
    backendStatus = tr("chat.backendStarting") || "Starting backend...";
    if (eventsProcess.running) {
      suppressNextEventsExit = true;
      eventsProcess.signal(15);
    }
    Quickshell.execDetached(helperCommandArgs("daemon", null, 0));
    subscribeStartTimer.restart();
    stateRefreshTimer.restart();
    backendStartupWatchdogTimer.restart();
  }

  function markBackendReady() {
    backendRetryAttempts = 0;
    backendRetryTimer.stop();
    backendStartupWatchdogTimer.stop();
  }

  function scheduleBackendRetry(reason) {
    if (backendReady || backendRetryTimer.running)
      return;
    startingBackend = false;
    backendRetryAttempts += 1;
    const delay = Math.min(15000, 1000 * Math.pow(2, Math.min(backendRetryAttempts - 1, 4)));
    backendRetryTimer.interval = delay;
    backendStatus = (tr("chat.backendRetrying") || "Backend not ready; retrying") + " (" + Math.round(delay / 1000) + "s)";
    if (reason)
      Logger.w("[pi-assistant-panel] scheduling backend retry:", reason);
    backendRetryTimer.restart();
  }

  function restartBackend(resetRetryAttempts) {
    if (resetRetryAttempts !== false)
      backendRetryAttempts = 0;
    startingBackend = false;
    backendReady = false;
    isGenerating = false;
    currentResponse = "";
    resetTransientPanels();
    modelsLoading = false;
    commandsLoading = false;
    backendCwd = "";
    backendModelInfo = null;
    backendContextUsage = null;
    modelChangeInProgress = false;
    availableModels = [];
    availableCommands = builtinSlashCommands();
    backendStatus = tr("chat.backendRestarting") || "Restarting backend...";
    if (eventsProcess.running) {
      suppressNextEventsExit = true;
      eventsProcess.signal(15);
    }
    Quickshell.execDetached(helperCommandArgs("command", { "command": "shutdown" }, 1));
    backendRestartTimer.restart();
  }

  function sendCommand(payload, callback) {
    if (commandProcess.running)
      return false;
    pendingCommandCallback = callback || null;
    pendingCommandName = payload?.command || "";
    commandProcess.command = helperCommandArgs("command", payload, 5);
    commandProcess.running = true;
    return true;
  }

  function appendMessage(role, content) {
    const newMessage = {
      "id": Date.now().toString() + "-" + Math.round(Math.random() * 10000),
      "role": role,
      "content": content,
      "timestamp": new Date().toISOString()
    };
    const next = Array.from(messages);
    next.push(newMessage);
    messages = next.slice(-maxHistoryLength);
  }

  function messageTextContent(value) {
    if (value === null || value === undefined)
      return "";
    if (typeof value === "string")
      return value;
    if (Array.isArray(value)) {
      const parts = [];
      for (const item of value) {
        if (typeof item === "string") {
          parts.push(item);
        } else if (item?.type === "text" && item?.text !== undefined) {
          parts.push(item.text);
        } else if (item?.text !== undefined) {
          parts.push(String(item.text));
        }
      }
      return parts.join("\n\n").trim();
    }
    if (typeof value === "object" && value.text !== undefined)
      return String(value.text);
    return "";
  }

  function restoreMessagesFromBackend() {
    if (!backendReady)
      return false;
    if (commandProcess.running) {
      historyRefreshTimer.restart();
      return false;
    }
    return sendCommand({ "command": "get_messages" }, function (reply) {
      if (!reply?.ok)
        return;
      const rawMessages = reply?.response?.data?.messages || [];
      const restored = [];
      for (const msg of rawMessages) {
        const role = msg?.role || "";
        if (role !== "user" && role !== "assistant")
          continue;
        const text = messageTextContent(msg?.content);
        if (!text)
          continue;
        restored.push({
          "id": String(msg?.id || msg?.timestamp || (Date.now() + "-" + restored.length)),
          "role": role,
          "content": text,
          "timestamp": msg?.timestamp ? String(msg.timestamp) : new Date().toISOString()
        });
      }
      messages = restored.slice(-maxHistoryLength);
    });
  }

  function handleSlashCommand(text) {
    const trimmed = (text || "").trim();
    if (!trimmed.startsWith("/"))
      return false;
    const firstSpace = trimmed.indexOf(" ");
    const commandName = (firstSpace >= 0 ? trimmed.slice(0, firstSpace) : trimmed).toLowerCase();
    const args = firstSpace >= 0 ? trimmed.slice(firstSpace + 1).trim() : "";

    if (commandName === "/new") {
      clearMessages();
      return true;
    }

    if (commandName === "/clear") {
      clearMessages();
      return true;
    }

    if (commandName === "/compact") {
      sendCommand({ "command": "compact" }, function (reply) {
        if (!reply?.ok) {
          errorMessage = reply?.error || tr("errors.requestFailed") || "Request failed.";
          return;
        }
        appendMessage("assistant", "Session compacted.");
        stateRefreshTimer.restart();
      });
      return true;
    }

    if (commandName === "/session") {
      sendCommand({ "command": "get_session_stats" }, function (reply) {
        if (!reply?.ok) {
          errorMessage = reply?.error || tr("errors.requestFailed") || "Request failed.";
          return;
        }
        const stats = reply?.response?.data || {};
        const context = stats?.contextUsage || {};
        appendMessage("assistant", "Session: " + (stats?.sessionName || sessionName) + "\nMessages: " + (stats?.totalMessages ?? 0) + "\nContext: " + formatContextIndicator(context, backendModelInfo));
        backendContextUsage = context;
      });
      return true;
    }

    if (commandName === "/name") {
      if (!args) {
        errorMessage = "Usage: /name <session name>";
        return true;
      }
      sendCommand({ "command": "set_session_name", "name": args }, function (reply) {
        if (!reply?.ok) {
          errorMessage = reply?.error || tr("errors.requestFailed") || "Request failed.";
          return;
        }
        appendMessage("assistant", "Session renamed to: " + args);
      });
      return true;
    }

    if (commandName === "/thinking" || commandName === "/think") {
      const nextLevel = args.toLowerCase();
      if (!nextLevel) {
        appendMessage("assistant", "Current thinking level: " + (backendThinkingLevel || thinkingLevel || "medium"));
        return true;
      }
      const started = setActiveThinkingLevel(nextLevel);
      if (!started) {
        const allowedLevels = ["off", "minimal", "low", "medium", "high", "xhigh"];
        if (allowedLevels.indexOf(nextLevel) < 0)
          errorMessage = "Usage: /thinking <off|minimal|low|medium|high|xhigh>";
      } else {
        appendMessage("assistant", "Thinking level set to: " + nextLevel);
      }
      return true;
    }

    if (commandName === "/model") {
      appendMessage("assistant", "Use the model dropdown at the top of the panel to change models.");
      return true;
    }

    return false;
  }

  function resetTransientPanels() {
    currentThinking = "";
    currentToolEvents = [];
  }

  function updateToolEvent(toolCallId, toolName, update) {
    const next = Array.from(currentToolEvents || []);
    const id = toolCallId || (toolName + "-" + next.length);
    let index = -1;
    for (let i = 0; i < next.length; ++i) {
      if (next[i]?.toolCallId === id) {
        index = i;
        break;
      }
    }
    const entry = index >= 0 ? Object.assign({}, next[index]) : {
      "toolCallId": id,
      "toolName": toolName || "tool",
      "status": "running",
      "summary": "",
      "details": "",
      "isError": false
    };
    for (const key in (update || {}))
      entry[key] = update[key];
    if (index >= 0)
      next[index] = entry;
    else
      next.push(entry);
    currentToolEvents = next;
  }

  function summarizeToolPayload(value) {
    function formatPrimitive(item) {
      if (item === null || item === undefined)
        return "";
      if (typeof item === "string")
        return item;
      if (typeof item === "number" || typeof item === "boolean")
        return String(item);
      return "";
    }

    function formatValue(item, indent) {
      const primitive = formatPrimitive(item);
      if (primitive)
        return primitive;
      const prefix = " ".repeat(indent || 0);
      if (Array.isArray(item)) {
        const lines = [];
        for (const entry of item) {
          const formatted = formatValue(entry, (indent || 0) + 2);
          if (formatted)
            lines.push(prefix + "• " + formatted.replace(/\n/g, "\n" + prefix + "  "));
        }
        return lines.join("\n");
      }
      if (typeof item === "object") {
        const lines = [];
        for (const key of Object.keys(item || {})) {
          const formatted = formatValue(item[key], (indent || 0) + 2);
          if (!formatted)
            continue;
          if (formatted.indexOf("\n") >= 0)
            lines.push(prefix + key + ":\n" + formatted);
          else
            lines.push(prefix + key + ": " + formatted);
        }
        return lines.join("\n");
      }
      return String(item || "");
    }

    return formatValue(value, 0).trim();
  }

  function sendMessage(text, streamingBehavior) {
    const trimmed = (text || "").trim();
    if (!trimmed)
      return false;
    errorMessage = "";
    if (!backendReady && !startingBackend) {
      restartBackend();
      errorMessage = tr("errors.backendUnavailable") || "Pi backend is not ready yet.";
      return false;
    }
    if (!isGenerating && handleSlashCommand(trimmed))
      return true;

    const payload = { "command": "send", "message": trimmed };
    if (streamingBehavior)
      payload.streamingBehavior = streamingBehavior;

    const started = sendCommand(payload, function (reply) {
      if (reply?.ok) {
        if (streamingBehavior === "steer") {
          backendStatus = tr("chat.steeringQueued") || "Steering queued";
        } else if (streamingBehavior === "followUp") {
          backendStatus = tr("chat.followUpQueued") || "Follow-up queued";
        } else {
          appendMessage("user", trimmed);
          isGenerating = true;
          currentResponse = "";
        }
      } else {
        errorMessage = reply?.error || tr("errors.requestFailed") || "Request failed.";
      }
    });
    return started;
  }

  function stopGeneration() {
    if (!isGenerating)
      return;
    sendCommand({ "command": "abort" }, function (reply) {
      if (!reply?.ok && !errorMessage)
        errorMessage = reply?.error || tr("errors.requestFailed") || "Request failed.";
    });
  }

  function clearMessages() {
    messages = [];
    currentResponse = "";
    resetTransientPanels();
    errorMessage = "";
    isGenerating = false;
    backendContextUsage = null;
    sendCommand({ "command": "reset_session" }, function (reply) {
      if (!reply?.ok) {
        errorMessage = reply?.error || tr("errors.requestFailed") || "Request failed.";
        return;
      }
      stateRefreshTimer.restart();
    });
  }

  function refreshSessionStats() {
    if (!backendReady)
      return false;
    if (commandProcess.running) {
      statsRefreshTimer.restart();
      return false;
    }
    return sendCommand({ "command": "get_session_stats" }, function (reply) {
      if (!reply?.ok)
        return;
      backendContextUsage = reply?.response?.data?.contextUsage ?? backendContextUsage;
    });
  }

  function refreshState() {
    sendCommand({ "command": "get_state" }, function (reply) {
      if (!reply?.ok) {
        const message = reply?.error || "";
        if (message.indexOf("pi-backend-not-running") >= 0 || message.indexOf("cannot-connect") >= 0 || message.indexOf("backend") >= 0)
          scheduleBackendRetry(message);
        return;
      }
      const state = reply.state ?? reply.response?.data ?? {};
      backendReady = state.backendReady ?? true;
      backendCwd = state.cwd ?? backendCwd;
      backendModelInfo = state.model ?? backendModelInfo;
      backendModel = stringifyModel(state.model) || backendModel;
      backendThinkingLevel = state.thinkingLevel ?? backendThinkingLevel;
      backendStatus = backendReady ? (tr("chat.backendReady") || "Backend ready") : (tr("chat.backendNotReady") || "Backend not ready");
      if (backendReady) {
        markBackendReady();
        modelRefreshTimer.restart();
        commandRefreshTimer.restart();
        statsRefreshTimer.restart();
        historyRefreshTimer.restart();
      } else {
        scheduleBackendRetry(state.lastError || "backend not running");
      }
    });
  }

  function handleEventLine(line) {
    const text = (line || "").trim();
    if (!text)
      return;
    try {
      const event = JSON.parse(text);
      const type = event.type || "";
      if (type === "ready") {
        startingBackend = false;
        backendReady = event.state?.backendReady ?? true;
        backendCwd = event.state?.cwd ?? backendCwd;
        backendModelInfo = event.state?.model ?? backendModelInfo;
        backendModel = stringifyModel(event.state?.model) || backendModel;
        backendThinkingLevel = event.state?.thinkingLevel || backendThinkingLevel;
        if (backendReady) {
          markBackendReady();
          backendStatus = tr("chat.backendReady") || "Backend ready";
          modelRefreshTimer.restart();
          commandRefreshTimer.restart();
          statsRefreshTimer.restart();
          historyRefreshTimer.restart();
        } else {
          backendStatus = tr("chat.backendNotReady") || "Backend not ready";
          scheduleBackendRetry(event.state?.lastError || "backend not running");
        }
      } else if (type === "agent_start") {
        isGenerating = true;
        resetTransientPanels();
        backendReady = event.state?.backendReady ?? true;
        backendStatus = tr("chat.generating") || "Generating...";
      } else if (type === "text_delta") {
        isGenerating = true;
        currentResponse += event.delta || "";
      } else if (type === "thinking_delta") {
        isGenerating = true;
        currentThinking += event.delta || "";
      } else if (type === "tool_call") {
        isGenerating = true;
        updateToolEvent(event.toolCallId, event.toolName, {
          "status": "running",
          "summary": summarizeToolPayload(event.input)
        });
      } else if (type === "tool_result") {
        updateToolEvent(event.toolCallId, event.toolName, {
          "status": event.isError ? "error" : "done",
          "details": summarizeToolPayload(event.content),
          "isError": !!event.isError
        });
      } else if (type === "tool_execution_start") {
        isGenerating = true;
        updateToolEvent(event.toolCallId, event.toolName, {
          "status": "running",
          "summary": summarizeToolPayload(event.args)
        });
      } else if (type === "tool_execution_update") {
        updateToolEvent(event.toolCallId, event.toolName, {
          "status": "running",
          "details": summarizeToolPayload(event.partialResult)
        });
      } else if (type === "tool_execution_end") {
        updateToolEvent(event.toolCallId, event.toolName, {
          "status": event.isError ? "error" : "done",
          "details": summarizeToolPayload(event.result),
          "isError": !!event.isError
        });
      } else if (type === "done") {
        if (currentResponse.trim() !== "")
          appendMessage("assistant", currentResponse.trim());
        currentResponse = "";
        resetTransientPanels();
        isGenerating = false;
        backendReady = event.state?.backendReady ?? true;
        backendStatus = tr("chat.backendReady") || "Backend ready";
        stateRefreshTimer.restart();
        historyRefreshTimer.restart();
      } else if (type === "error") {
        const message = event.message || tr("errors.requestFailed") || "Request failed.";
        errorMessage = message;
        isGenerating = false;
        resetTransientPanels();
        startingBackend = false;
        const backendFailure = message.indexOf("backend") >= 0 || message.indexOf("cannot-connect") >= 0 || message.indexOf("exited") >= 0;
        if (backendFailure) {
          backendReady = false;
          backendStatus = tr("chat.backendNotReady") || "Backend not ready";
          scheduleBackendRetry(message);
        } else {
          backendStatus = backendReady ? (tr("chat.backendReady") || "Backend ready") : (tr("chat.backendNotReady") || "Backend not ready");
        }
      } else if (type === "status") {
        backendStatus = event.message || backendStatus;
        backendReady = event.state?.backendReady ?? backendReady;
      } else if (type === "backend_log") {
        Logger.w("[pi-assistant-panel]", event.message || "");
      } else if (type === "backend_exited") {
        backendReady = false;
        startingBackend = false;
        modelsLoading = false;
        commandsLoading = false;
        backendCwd = "";
        backendModelInfo = null;
        backendContextUsage = null;
        modelChangeInProgress = false;
        availableModels = [];
        availableCommands = builtinSlashCommands();
        backendStatus = tr("chat.backendExited") || "Backend exited";
        scheduleBackendRetry("backend exited");
      }
    } catch (error) {
      Logger.w("[pi-assistant-panel] invalid helper event:", text, error);
    }
  }

  onCurrentPanelScreenChanged: {
    if (currentPanelScreen) {
      lastPanelScreen = currentPanelScreen;
      if (panelPinned && standaloneScreen)
        closeStandaloneWindow();
    } else if (panelPinned && lastPanelScreen && !standaloneScreen) {
      repinTimer.restart();
    }
  }

  onPluginApiChanged: {
    if (pluginApi && !backendReady && !startingBackend)
      startBackend();
  }

  Component.onCompleted: {
    startBackend();
    if (panelPinned && lastPanelScreen)
      openStandaloneWindow(lastPanelScreen);
  }

  readonly property Timer subscribeStartTimer: Timer {
    interval: 800
    repeat: false
    onTriggered: {
      if (eventsProcess.running)
        eventsProcess.signal(15);
      eventsProcess.command = root.helperCommandArgs("subscribe", null, 15);
      eventsProcess.running = true;
    }
  }

  readonly property Timer backendRestartTimer: Timer {
    interval: 700
    repeat: false
    onTriggered: root.startBackend()
  }

  readonly property Timer backendStartupWatchdogTimer: Timer {
    interval: 7000
    repeat: false
    onTriggered: {
      if (!root.backendReady) {
        root.startingBackend = false;
        root.scheduleBackendRetry("backend startup timed out");
      }
    }
  }

  readonly property Timer repinTimer: Timer {
    interval: 120
    repeat: false
    onTriggered: root.reopenPinnedPanel()
  }

  Loader {
    active: root.panelPinned && !!root.standaloneScreen

    sourceComponent: FloatingChatWindow {
      screen: root.standaloneScreen
      pluginApi: root.pluginApi
      mainInstance: root
    }
  }

  readonly property Timer backendRetryTimer: Timer {
    interval: 1500
    repeat: false
    onTriggered: {
      if (!root.backendReady)
        root.restartBackend(false);
    }
  }

  readonly property Timer stateRefreshTimer: Timer {
    interval: 2000
    repeat: false
    onTriggered: root.refreshState()
  }

  readonly property Timer modelRefreshTimer: Timer {
    interval: 350
    repeat: false
    onTriggered: root.refreshAvailableModels()
  }

  readonly property Timer commandRefreshTimer: Timer {
    interval: 500
    repeat: false
    onTriggered: root.refreshAvailableCommands()
  }

  readonly property Timer historyRefreshTimer: Timer {
    interval: 650
    repeat: false
    onTriggered: root.restoreMessagesFromBackend()
  }

  readonly property Timer statsRefreshTimer: Timer {
    interval: 450
    repeat: false
    onTriggered: root.refreshSessionStats()
  }

  readonly property Process commandProcess: Process {
    running: false

    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0 && root.pendingCommandCallback) {
        root.pendingCommandCallback({
          "ok": false,
          "error": commandProcess.lastCommandStdout || commandProcess.lastCommandStderr || ("helper exited with code " + exitCode)
        });
      }
      root.pendingCommandCallback = null;
      root.pendingCommandName = "";
      commandProcess.lastCommandStdout = "";
      commandProcess.lastCommandStderr = "";
    }

    property string lastCommandStdout: ""
    property string lastCommandStderr: ""

    stdout: StdioCollector {
      onStreamFinished: {
        commandProcess.lastCommandStdout = text.trim();
        if (!commandProcess.lastCommandStdout)
          return;
        try {
          const reply = JSON.parse(commandProcess.lastCommandStdout);
          if (root.pendingCommandCallback) {
            const callback = root.pendingCommandCallback;
            root.pendingCommandCallback = null;
            callback(reply);
          }
        } catch (error) {
          if (root.pendingCommandCallback) {
            const callback = root.pendingCommandCallback;
            root.pendingCommandCallback = null;
            callback({
              "ok": false,
              "error": commandProcess.lastCommandStdout
            });
          }
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        commandProcess.lastCommandStderr = text.trim();
        if (commandProcess.lastCommandStderr)
          Logger.w("[pi-assistant-panel]", commandProcess.lastCommandStderr);
      }
    }
  }

  readonly property Process eventsProcess: Process {
    running: false

    stdout: SplitParser {
      onRead: data => root.handleEventLine(data)
    }

    stderr: StdioCollector {
      onStreamFinished: {
        const msg = text.trim();
        if (msg)
          Logger.w("[pi-assistant-panel]", msg);
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (root.suppressNextEventsExit) {
        root.suppressNextEventsExit = false;
        return;
      }
      if (exitCode !== 0) {
        root.backendReady = false;
        root.startingBackend = false;
        root.modelsLoading = false;
        root.commandsLoading = false;
        root.backendCwd = "";
        root.backendModelInfo = null;
        root.backendContextUsage = null;
        root.modelChangeInProgress = false;
        root.availableModels = [];
        root.availableCommands = root.builtinSlashCommands();
        root.backendStatus = root.tr("chat.backendNotReady") || "Backend not ready";
        root.scheduleBackendRetry("event subscriber exited with code " + exitCode);
      }
    }
  }

  IpcHandler {
    target: "plugin:pi-assistant-panel"

    function toggle() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          root.togglePreferredUI(screen);
        });
      }
    }

    function open() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          root.openPreferredUI(screen);
        });
      }
    }

    function close() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          root.closePreferredUI(screen);
        });
      }
    }

    function send(message) {
      if (message && message.trim() !== "")
        root.sendMessage(message);
    }

    function clear() {
      root.clearMessages();
    }

    function status() {
      return {
        backendReady: root.backendReady,
        isGenerating: root.isGenerating,
        model: root.resolvedModel,
        messageCount: root.messages.length
      };
    }
  }
}
