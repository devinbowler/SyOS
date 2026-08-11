# tools/normalize-eol.ps1 - rewrite every repo file with LF line endings.
#
# SyOS is edited on Windows and executed on Debian. Windows editors save
# CRLF, and a CRLF in a shell script makes bash fail with the memorably
# unhelpful "bad interpreter: /usr/bin/env bash^M" before printing anything.
# .gitattributes fixes what lands in git; this fixes the working tree, which
# matters when the tree is shared with a VM over a folder mount.
#
# Usage (from the repo root):  pwsh -File tools/normalize-eol.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$converted = 0

Get-ChildItem -Path $root -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\\.git\\' } |
    ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        # 13 = CR. Skip binaries and files that are already clean.
        if ($bytes -notcontains 13) { return }

        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        $normalized = $text -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($_.FullName, $normalized, $utf8NoBom)

        Write-Output ("  LF  " + $_.FullName.Substring($root.Length + 1))
        $converted++
    }

Write-Output "line endings: $converted file(s) converted"
