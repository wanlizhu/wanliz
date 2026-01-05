Remove-Item -LiteralPath "build-windows" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path "build-windows" -Force | Out-Null
Set-Location -LiteralPath "build-windows"

cmake .. -DCMAKE_BUILD_TYPE=Debug 
if ($LASTEXITCODE -ne 0) { exit 1 }

cmake --build . 
if ($LASTEXITCODE -ne 0) { exit 1 }
