<?php
// Minimal FastCGI client, so tests can talk to php-fpm the way the pod's web container does.
// Usage: php fcgi.php <script_filename> [script_name] [host] [port]
// Prints the response body; exits non-zero on connection failure or an empty response.

$script = $argv[1] ?? '';
$name = $argv[2] ?? '/' . basename($script);
$host = $argv[3] ?? '127.0.0.1';
$port = (int) ($argv[4] ?? 9000);

$sock = @fsockopen($host, $port, $errno, $errstr, 5);
if (!$sock) {
    fwrite(STDERR, "connect {$host}:{$port} failed: {$errstr}\n");
    exit(1);
}

function record(int $type, string $content): string
{
    return pack('CCnnCx', 1, $type, 1, strlen($content), 0) . $content;
}

function pair(string $name, string $value): string
{
    $len = fn (string $s): string => strlen($s) < 128 ? chr(strlen($s)) : pack('N', strlen($s) | 0x80000000);
    return $len($name) . $len($value) . $name . $value;
}

$params = [
    'GATEWAY_INTERFACE' => 'CGI/1.1',
    'REQUEST_METHOD' => 'GET',
    'SCRIPT_FILENAME' => $script,
    'SCRIPT_NAME' => $name,
    'REQUEST_URI' => $name,
    'QUERY_STRING' => '',
    'SERVER_PROTOCOL' => 'HTTP/1.1',
    'SERVER_NAME' => 'localhost',
    'SERVER_PORT' => '80',
    'REMOTE_ADDR' => '127.0.0.1',
];
$encoded = '';
foreach ($params as $k => $v) {
    $encoded .= pair($k, $v);
}

// BEGIN_REQUEST (responder role), PARAMS, empty PARAMS, empty STDIN
fwrite($sock, record(1, pack('nCx5', 1, 0)) . record(4, $encoded) . record(4, '') . record(5, ''));

$stdout = '';
while (!feof($sock)) {
    $header = fread($sock, 8);
    if ($header === false || strlen($header) < 8) {
        break;
    }
    $r = unpack('Cversion/Ctype/nid/nlength/Cpadding/Creserved', $header);
    $content = $r['length'] > 0 ? stream_get_contents($sock, $r['length']) : '';
    if ($r['padding'] > 0) {
        fread($sock, $r['padding']);
    }
    if ($r['type'] === 6) {
        $stdout .= $content;
    } elseif ($r['type'] === 7) {
        fwrite(STDERR, $content);
    } elseif ($r['type'] === 3) {
        break;
    }
}

$parts = explode("\r\n\r\n", $stdout, 2);
$body = $parts[1] ?? $stdout;
echo $body;
exit($body === '' ? 1 : 0);
