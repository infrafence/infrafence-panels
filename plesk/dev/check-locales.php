<?php
// Checks that every locale file defines exactly the keys of en-US, with the same %%placeholders%%.
// Run: php dev/check-locales.php   (build.sh runs it in a php:cli container)

$dir = __DIR__ . '/../src/plib/resources/locales';

function flatten(array $tree, string $prefix = ''): array
{
    $flat = [];
    foreach ($tree as $key => $value) {
        if (is_array($value)) {
            $flat += flatten($value, $prefix . $key . '.');
        } else {
            $flat[$prefix . $key] = $value;
        }
    }
    return $flat;
}

function load(string $file): array
{
    $messages = null;
    include $file;
    if (!is_array($messages)) {
        fwrite(STDERR, "$file does not define \$messages\n");
        exit(1);
    }
    return flatten($messages);
}

function placeholders(string $text): array
{
    preg_match_all('/%%(\w+)%%/', $text, $m);
    sort($m[1]);
    return $m[1];
}

$reference = load("$dir/en-US.php");
$expected = ['de-DE', 'es-ES', 'fr-FR', 'it-IT', 'pt-BR', 'pt-PT'];
$failed = false;

foreach ($expected as $code) {
    $file = "$dir/$code.php";
    if (!is_file($file)) {
        echo "$code: missing\n";
        $failed = true;
        continue;
    }
    $messages = load($file);
    foreach (array_diff_key($reference, $messages) as $key => $_) {
        echo "$code: missing key $key\n";
        $failed = true;
    }
    foreach (array_diff_key($messages, $reference) as $key => $_) {
        echo "$code: unknown key $key\n";
        $failed = true;
    }
    foreach (array_intersect_key($messages, $reference) as $key => $text) {
        if (placeholders($text) !== placeholders($reference[$key])) {
            echo "$code: placeholders differ in $key\n";
            $failed = true;
        }
    }
}

echo $failed ? "locale check failed\n" : 'locale check passed: en-US + ' . implode(', ', $expected) . ' (' . count($reference) . " keys)\n";
exit($failed ? 1 : 0);
