# .\get_pokemon_data.ps1 -MinId 1 -MaxId 3 -OutputPath "pokemon_data.json" -UseLocalSprites
param(
    [string]$OutputPath = "pokemon_movesets.json"
)

# API Base URL
$baseUrl = "https://pokeapi.co/api/v2"

# Gen 1 and Gen 2 Pokémon (1-251)
$minId = 1
$maxId = 251

# Output file location
$outputFile = Join-Path -Path (Get-Location) -ChildPath $OutputPath

# Array to store all Pokémon data
$allPokemon = @()

Write-Host "Fetching Pokémon moveset data (IDs $minId-$maxId)..." -ForegroundColor Cyan

for ($id = $minId; $id -le $maxId; $id++) {
    try {
        Write-Progress -Activity "Fetching Pokémon data" -Status "Pokémon $id / $maxId" -PercentComplete (($id - $minId) / ($maxId - $minId) * 100)
        
        # Fetch Pokémon data
        $pokemonUrl = "$baseUrl/pokemon/$id"
        $pokemonResponse = Invoke-RestMethod -Uri $pokemonUrl -TimeoutSec 10
        
        # Extract moveset
        $moves = @()
        foreach ($moveData in $pokemonResponse.moves) {
            $moves += @{
                name = $moveData.move.name
                level = ($moveData.version_group_details | Where-Object { $_.version_group.name -match "^(red-blue|gold-silver|crystal)$" } | Select-Object -First 1).level_learned_at
                method = ($moveData.version_group_details | Where-Object { $_.version_group.name -match "^(red-blue|gold-silver|crystal)$" } | Select-Object -First 1).move_learn_method.name
            }
        }
        
        # Create Pokémon entry
        $pokemonEntry = @{
            id = $pokemonResponse.id
            name = $pokemonResponse.name
            gen = if ($pokemonResponse.id -le 151) { 1 } else { 2 }
            moves = $moves
        }
        
        $allPokemon += $pokemonEntry
    }
    catch {
        Write-Host "Error fetching Pokémon $id : $_" -ForegroundColor Red
        continue
    }
}

Write-Progress -Activity "Fetching Pokémon data" -Completed

# Convert to JSON and save
$json = $allPokemon | ConvertTo-Json -Depth 10

Set-Content -Path $outputFile -Value $json -Encoding UTF8

Write-Host "`nMovesets saved to: $outputFile" -ForegroundColor Green
Write-Host "Total Pokémon: $($allPokemon.Count)" -ForegroundColor Green
