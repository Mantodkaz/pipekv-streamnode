<?php
$id = $_GET['v'] ?? '';
if (!preg_match('/^[a-zA-Z0-9_\-]+$/', $id)) {
    header("Location: /");
    exit;
}

$filename = $id . '.m3u8';
$cache_file = __DIR__ . '/m3u8_index_cache.json';

if (!file_exists($cache_file)) {
    header("Location: /");
    exit;
}

//read cache
$cached = json_decode(file_get_contents($cache_file), true);
if (!is_array($cached) || !in_array($filename, $cached, true)) {
    header("Location: /");
    exit;
}

$currentIndex = array_search($filename, $cached, true);
$nextId = '';

if ($currentIndex !== false && isset($cached[$currentIndex + 1])) {
    $nextFile = basename($cached[$currentIndex + 1], '.m3u8');
    $nextId = $nextFile;
}

// replace this 127.0.0.1 with your site/ip (must using port 6969)
$m3u8_url = "https://127.0.0.1:6969/m3u8/" . rawurlencode($filename);
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title><?= htmlspecialchars($id) ?></title>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        html, body {
            margin: 0;
            padding: 0;
            background: #111;
            color: #0f0;
            font-family: monospace;
            display: flex;
            flex-direction: column;
            align-items: center;
        }

        #back-btn {
            margin-top: 1em;
            padding: 0.5em 1.2em;
            background: #0f0;
            color: #111;
            border: none;
            border-radius: 4px;
            font-weight: bold;
            font-family: monospace;
            cursor: pointer;
            text-decoration: none;
        }

        #back-btn:hover {
            background: #5f5;
        }

        video {
            width: 100%;
            max-width: 960px;
            height: auto;
            margin-top: 1em;
            border: 2px solid #0f0;
            box-sizing: border-box;
        }

        #info {
            width: 100%;
            max-width: 960px;
            margin: 1em;
            padding: 1em;
            background: #222;
            color: #0f0;
            font-size: 14px;
            white-space: pre-wrap;
            overflow-y: auto;
            max-height: 160px;
            box-sizing: border-box;
            border: 1px solid #0f0;
        }
    </style>
</head>
<body>
    <button id="back-btn">← Back to Playlist</button>
    <video id="video" controls autoplay></video>
    <div id="info">Latency info...</div>

<script>
const video = document.getElementById('video');
const info = document.getElementById('info');
const m3u8Url = <?= json_encode($m3u8_url) ?>;
const nextId = <?= json_encode($nextId) ?>;
const fetchTimestamps = {};
const logBuffer = [];

document.getElementById('back-btn').addEventListener('click', () => {
    window.location.href = '/';
});

function addLog(line) {
    logBuffer.unshift(line);
    if (logBuffer.length > 5) logBuffer.pop();
    info.textContent = logBuffer.join("\n");
}

if (Hls.isSupported()) {
    const hls = new Hls({
        xhrSetup: function(xhr, url) {
            const tsName = url.split('/ts/')[1] || 'unknown.ts';
            fetchTimestamps[tsName] = Date.now();

            xhr.addEventListener("loadend", function() {
                const end = Date.now();
                const start = fetchTimestamps[tsName] || end;
                const latencyMs = end - start;
                const latencySec = (latencyMs / 1000).toFixed(3);
                const line = `[${new Date().toLocaleTimeString()}] ${tsName} - Read latency: ${latencySec} s`;
                addLog(line);
            });
        }
    });

    hls.loadSource(m3u8Url);
    hls.attachMedia(video);

    video.addEventListener('ended', () => {
        if (nextId) {
            window.location.href = 'player?v=' + encodeURIComponent(nextId);
        }
    });
} else if (video.canPlayType('application/vnd.apple.mpegurl')) {
    video.src = m3u8Url;
    video.addEventListener('ended', () => {
        if (nextId) {
            window.location.href = 'player?v=' + encodeURIComponent(nextId);
        }
    });
}
</script>
</body>
</html>
