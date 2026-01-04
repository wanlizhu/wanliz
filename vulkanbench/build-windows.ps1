$regen_clangd_db = ($args[0] -eq "--regen-clangd-db")
$build_dir = if ($regen_clangd_db) { "build-windows-temp" } else { "build-windows" }

Remove-Item -LiteralPath $build_dir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $build_dir -Force | Out-Null
Set-Location -LiteralPath $build_dir

if ($regen_clangd_db) {
    cmake .. -GNinja -DCMAKE_BUILD_TYPE=Debug 
} else {
    cmake .. -DCMAKE_BUILD_TYPE=Debug 
}
if ($LASTEXITCODE -ne 0) { exit 1 }

cmake --build . 
if ($LASTEXITCODE -ne 0) { exit 1 }

if ($regen_clangd_db) {
    Copy-Item -Force -Verbose -Path "compile_commands.json" -Destination ".." -ErrorAction Stop
    Set-Location ".." 
    Remove-Item -Recurse -Force $build_dir -ErrorAction SilentlyContinue
    (Get-Content .clangd) | Set-Content .clangd
}
