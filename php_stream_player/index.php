<?php
$files = json_decode(@file_get_contents(__DIR__ . '/m3u8_index_cache.json'), true) ?: [];

function formatTimeFromId($id) {
    if (preg_match('/_(\d{13})$/', $id, $m)) {
        $ts = (int)($m[1] / 1000);
        return date("Y-m-d H:i:s", $ts);
    }
    return '?';
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>My Playlist Test</title>
    <style>
        body {
            background: #0d0d0d;
            color: #f0f0f0;
            font-family: system-ui, sans-serif;
            margin: 2rem;
        }
        h1 { color: #00d0ff; }
        ul { list-style: none; padding: 0; }
        li { margin: 0.5rem 0; }
        a {
            color: #80d4ff;
            text-decoration: none;
            background: #1a1a1a;
            border-radius: 4px;
            padding: 0.4rem 0.6rem;
            display: inline-block;
            transition: background 0.2s ease;
        }
        a:hover { background: #2e2e2e; }
    </style>
</head>
<body>
    <h1>My Playlist Test</h1>
    <ul>
        <?php foreach ($files as $file):
            $base = basename($file, '.m3u8');
            $parts = explode('_', $base, 2);
            $title = $parts[0];
            $humanTime = formatTimeFromId($base);
        ?>
        <li>
            <a href="player?v=<?= urlencode($base) ?>">
                <?= htmlspecialchars($title) ?> <small>(<?= $humanTime ?>)</small>
            </a>
        </li>
        <?php endforeach; ?>
    </ul>
</body>
</html>
