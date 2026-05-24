// Soniox Speech-to-Speech Translation — Sandbox Frontend

(function () {
  "use strict";

  const TTS_SAMPLE_RATE = 24000;

  var VOICES = ["Adrian", "Claire", "Daniel", "Emma", "Grace", "Jack", "Kenji", "Maya", "Mina", "Nina", "Noah", "Owen"];
  var LANGUAGES = [
    ["zh", "中文"], ["en", "English"], ["ja", "日本語"], ["ko", "한국어"],
    ["fr", "Français"], ["de", "Deutsch"], ["es", "Español"], ["pt", "Português"],
    ["ru", "Русский"], ["ar", "العربية"], ["th", "ไทย"], ["vi", "Tiếng Việt"],
    ["id", "Indonesian"], ["it", "Italiano"], ["nl", "Nederlands"],
  ];

  // DOM refs
  var $targetLang, $voice, $langId, $tts, $actionBtn, $actionLabel, $originalCol, $translationCol, $status;

  var ws = null, state = "idle", mediaRecorder = null, audioCtx = null;
  var nextPlayTime = 0, utterances = [], currentUtt;

  function showError(msg) {
    console.error(msg);
    setStatus("错误: " + msg);
    var el = document.getElementById("error-banner");
    if (el) { el.textContent = msg; el.style.display = "block"; }
  }

  function clearError() {
    var el = document.getElementById("error-banner");
    if (el) el.style.display = "none";
  }

  function initDOM() {
    $targetLang = document.getElementById("target-language");
    $voice = document.getElementById("voice");
    $langId = document.getElementById("lang-id");
    $tts = document.getElementById("tts");
    $actionBtn = document.getElementById("action");
    $actionLabel = $actionBtn ? $actionBtn.querySelector(".btn-label") : null;
    $originalCol = document.getElementById("original");
    $translationCol = document.getElementById("translation");
    $status = document.getElementById("status");

    var missing = [];
    if (!$targetLang) missing.push("target-language");
    if (!$voice) missing.push("voice");
    if (!$langId) missing.push("lang-id");
    if (!$tts) missing.push("tts");
    if (!$actionBtn) missing.push("action");
    if (!$originalCol) missing.push("original");
    if (!$translationCol) missing.push("translation");
    if (!$status) missing.push("status");
    if (missing.length) {
      alert("DOM 元素缺失: " + missing.join(", "));
      return false;
    }
    return true;
  }

  // Populate dropdowns
  function populateDropdowns() {
    LANGUAGES.forEach(function (pair) {
      var opt = document.createElement("option");
      opt.value = pair[0]; opt.textContent = pair[1];
      $targetLang.appendChild(opt);
    });
    $targetLang.value = "en";

    VOICES.forEach(function (name) {
      var opt = document.createElement("option");
      opt.value = name; opt.textContent = name;
      $voice.appendChild(opt);
    });
    $voice.value = "Maya";
  }

  // ---- WebSocket ----
  function openWebSocket() {
    var proto = location.protocol === "https:" ? "wss:" : "ws:";
    var params = new URLSearchParams({
      target_lang: $targetLang.value,
      lang_id: $langId.checked,
      diarize: false,
      voice: $voice.value,
      tts: $tts.checked,
    });
    var url = proto + "//" + location.host + "/ws/translate?" + params;
    console.log("[WS] connecting:", url);

    ws = new WebSocket(url);
    ws.binaryType = "arraybuffer";

    ws.onmessage = function (event) {
      if (typeof event.data === "string") {
        var data = JSON.parse(event.data);
        if (data.error_code) {
          showError("Soniox: " + data.error_code + " - " + (data.error_message || ""));
          return;
        }
        handleSttResult(data);
      } else {
        handleTtsAudio(new Uint8Array(event.data));
      }
    };

    return new Promise(function (resolve, reject) {
      ws.onopen = function () { console.log("[WS] open"); resolve(); };
      ws.onerror = function (e) { console.error("[WS] error", e); reject(new Error("WebSocket 连接失败")); };
      ws.onclose = function (ev) { console.log("[WS] close", ev.code, ev.reason); };
    });
  }

  function handleSttResult(data) {
    if (data.session_done) { console.log("[WS] session_done"); stop(); return; }

    currentUtt.originalPartial = "";
    currentUtt.translationPartial = "";

    var tokens = data.tokens || [];
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i];
      if (!t.text) continue;
      if (t.text === "<end>") {
        if (currentUtt.originalFinal || currentUtt.translationFinal ||
            currentUtt.originalPartial || currentUtt.translationPartial) {
          utterances.push(currentUtt);
          currentUtt = newUtt();
        }
        continue;
      }
      var isTranslation = t.translation_status === "translation";
      var spokenLang = isTranslation ? t.source_language : t.language;
      if (spokenLang) currentUtt.language = spokenLang;
      var side = isTranslation ? "translation" : "original";
      if (t.is_final) {
        currentUtt[side + "Final"] += t.text;
      } else {
        currentUtt[side + "Partial"] += t.text;
      }
    }
    render();
  }

  function newUtt() {
    return { language: null, originalFinal: "", originalPartial: "", translationFinal: "", translationPartial: "" };
  }

  // ---- Recorder ----
  async function startRecorder() {
    console.log("[mic] requesting getUserMedia...");
    var stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch (e) {
      throw new Error("麦克风权限被拒绝或不可用: " + e.message);
    }
    console.log("[mic] got stream");
    mediaRecorder = new MediaRecorder(stream);
    mediaRecorder.ondataavailable = function (e) {
      if (e.data.size > 0 && ws && ws.readyState === WebSocket.OPEN) {
        ws.send(e.data);
      }
    };
    mediaRecorder.start(100);
    console.log("[mic] recording started");
  }

  // ---- Audio playback ----
  function handleTtsAudio(chunk) {
    playPcmChunk(chunk);
  }

  function playPcmChunk(chunk) {
    if (!audioCtx) return;
    var evenLen = chunk.byteLength - (chunk.byteLength % 2);
    var int16 = new Int16Array(chunk.buffer, chunk.byteOffset, evenLen / 2);
    var float32 = new Float32Array(int16.length);
    for (var i = 0; i < int16.length; i++) float32[i] = int16[i] / 32768;
    var buffer = audioCtx.createBuffer(1, float32.length, TTS_SAMPLE_RATE);
    buffer.getChannelData(0).set(float32);
    var source = audioCtx.createBufferSource();
    source.buffer = buffer;
    source.connect(audioCtx.destination);
    var startAt = Math.max(audioCtx.currentTime, nextPlayTime);
    source.start(startAt);
    nextPlayTime = startAt + buffer.duration;
  }

  function resetSession() {
    if (audioCtx) { audioCtx.close().catch(function () {}); }
    audioCtx = new AudioContext({ sampleRate: TTS_SAMPLE_RATE });
    nextPlayTime = 0;
    utterances = [];
    currentUtt = newUtt();
    render();
  }

  // ---- Lifecycle ----
  async function start() {
    console.log("[start] begin");
    clearError();
    setState("recording");
    resetSession();
    try {
      console.log("[start] opening WS...");
      await openWebSocket();
      console.log("[start] starting recorder...");
      await startRecorder();
      console.log("[start] success");
    } catch (err) {
      console.error("[start] error:", err);
      showError(err.message || String(err));
      setState("idle");
      cleanup();
    }
  }

  function stop() {
    console.log("[stop]");
    setState("idle");
    cleanup();
  }

  function cleanup() {
    if (mediaRecorder) {
      if (mediaRecorder.state !== "inactive") { try { mediaRecorder.stop(); } catch (e) {} }
      if (mediaRecorder.stream) {
        mediaRecorder.stream.getTracks().forEach(function (t) { t.stop(); });
      }
    }
    mediaRecorder = null;
    if (ws) { try { ws.close(); } catch (e) {}; ws = null; }
  }

  // ---- UI state ----
  function setState(s) {
    state = s;
    var busy = s !== "idle";
    if (busy) {
      if ($actionLabel) $actionLabel.textContent = "停止";
      $actionBtn.dataset.state = "running";
    } else {
      $actionBtn.dataset.state = "idle";
      if ($actionLabel) $actionLabel.textContent = "开始说话";
    }
    $targetLang.disabled = busy;
    $voice.disabled = busy;
    $langId.disabled = busy;
    $tts.disabled = busy;
    if (s === "recording") setStatus("聆听中…");
    else setStatus("就绪");
  }

  function setStatus(msg) { if ($status) $status.textContent = msg; }

  // ---- Rendering ----
  function renderUtterance(u, col, side) {
    var final = u[side + "Final"];
    var partial = u[side + "Partial"];
    if (!final && !partial) return;

    var div = document.createElement("div");
    div.className = "utterance";

    var labels = [];
    if (side === "original" && $langId.checked && u.language) labels.push(u.language);
    else if (side === "translation" && $langId.checked) labels.push($targetLang.value);
    if (labels.length) {
      var lbl = document.createElement("div");
      lbl.className = "label"; lbl.textContent = labels.join(" · ");
      div.appendChild(lbl);
    }
    if (final) {
      var fs = document.createElement("span");
      fs.textContent = final;
      div.appendChild(fs);
    }
    if (partial) {
      var ps = document.createElement("span");
      ps.className = "partial"; ps.textContent = partial;
      div.appendChild(ps);
    }
    col.appendChild(div);
  }

  function render() {
    $originalCol.innerHTML = "";
    $translationCol.innerHTML = "";
    var all = utterances.concat([currentUtt]);
    for (var i = 0; i < all.length; i++) {
      renderUtterance(all[i], $originalCol, "original");
      renderUtterance(all[i], $translationCol, "translation");
    }
    syncRowHeights();
    $originalCol.scrollTop = $originalCol.scrollHeight;
    $translationCol.scrollTop = $translationCol.scrollHeight;
  }

  function syncRowHeights() {
    var o = $originalCol.children, t = $translationCol.children;
    for (var i = 0; i < o.length; i++) o[i].style.minHeight = "";
    for (var j = 0; j < t.length; j++) t[j].style.minHeight = "";
    var n = Math.min(o.length, t.length);
    for (var k = 0; k < n; k++) {
      var h = Math.max(o[k].offsetHeight, t[k].offsetHeight);
      o[k].style.minHeight = h + "px";
      t[k].style.minHeight = h + "px";
    }
  }

  // ---- Entry point ----
  function main() {
    if (!initDOM()) return;
    populateDropdowns();
    currentUtt = newUtt();
    setState("idle");

    $actionBtn.addEventListener("click", function () {
      console.log("[click] state=" + state);
      if (state !== "idle") stop(); else start();
    });

    console.log("[app] ready");
  }

  document.addEventListener("DOMContentLoaded", main);
})();
