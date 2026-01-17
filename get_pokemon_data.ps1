param(
    [int]$MinId = 1,
    [int]$MaxId = 151,
    [string]$OutputPath = "pokemon_data.json",
    [switch]$UseLocalSprites
)

$baseUrl = "https://pokeapi.co/api/v2"
$outputFile = Join-Path -Path (Get-Location) -ChildPath $OutputPath
$pokemonData = @{}

# Mapping from PokéAPI stat names to Lua stat names
$statMapping = @{
    "hp" = "hp"
    "attack" = "attack"
    "defense" = "defense"
    "special-attack" = "spAttack"
    "special-defense" = "spDefense"
    "speed" = "speed"
}

# Mapping from PokéAPI growth rate names to Lua growth rate names
$growthRateMapping = @{
    "slow" = "slow"
    "medium" = "medium_fast"
    "medium-slow" = "medium_slow"
    "fast" = "fast"
    "slow-then-very-fast" = "erratic"
    "fast-then-very-slow" = "fluctuating"
}

Write-Host "Fetching Pokémon data (IDs $MinId-$MaxId)..." -ForegroundColor Cyan

for ($id = $MinId; $id -le $MaxId; $id++) {
    try {
        Write-Progress -Activity "Fetching Pokémon data" -Status "Pokémon $id / $MaxId" -PercentComplete (($id - $MinId) / ($MaxId - $MinId) * 100)
        
        # Fetch main Pokémon data
        $pokemonUrl = "$baseUrl/pokemon/$id"
        Write-Host "Fetching: $pokemonUrl" -ForegroundColor Gray
        $pokemon = Invoke-RestMethod -Uri $pokemonUrl -TimeoutSec 10
        Write-Host "Got Pokémon: $($pokemon.name)" -ForegroundColor Green
        
        # Fetch species data
        $speciesUrl = $pokemon.species.url
        Write-Host "Fetching species: $speciesUrl" -ForegroundColor Gray
        $species = Invoke-RestMethod -Uri $speciesUrl -TimeoutSec 10
        Write-Host "Got species data" -ForegroundColor Green
        
        # Extract types (sorted by slot - slot 1 is primary type)
        $types = @($pokemon.types | Sort-Object slot | ForEach-Object { $_.type.name })
        
        # Extract base stats
        $baseStats = @{}
        foreach ($stat in $pokemon.stats) {
            $luaName = $statMapping[$stat.stat.name]
            $baseStats[$luaName] = $stat.base_stat
        }
        
        # Extract abilities (non-hidden only for now)
        $abilities = @()
        $hiddenAbility = $null
        foreach ($ability in $pokemon.abilities) {
            if ($ability.is_hidden) {
                $hiddenAbility = $ability.ability.name
            } else {
                $abilities += $ability.ability.name
            }
        }
        
        # Extract moves and organize by level (for learnset) - ONLY LEVEL UP
        $learnset = [ordered]@{}
        
        foreach ($moveData in $pokemon.moves) {
            # Get Gen 1 or Gen 2 moveset
            $moveInfo = $moveData.version_group_details | Where-Object { $_.version_group.name -match "^(red-blue|gold-silver|crystal)$" } | Select-Object -First 1
            
            if ($moveInfo) {
                # Only include level-up moves
                if ($moveInfo.move_learn_method.name -eq "level-up") {
                    $level = $moveInfo.level_learned_at
                    $moveName = $moveData.move.name -replace "-", "_"
                    
                    # Use string keys for JSON compatibility
                    $levelKey = [string]$level
                    
                    if (-not $learnset[$levelKey]) {
                        $learnset[$levelKey] = @()
                    }
                    $learnset[$levelKey] += $moveName
                }
            }
        }
        
        # Get evolution info - fetch from evolution chain endpoint
        $evolution = @{}
        if ($species.evolution_chain) {
            try {
                $chainUrl = $species.evolution_chain.url
                $chain = Invoke-RestMethod -Uri $chainUrl -TimeoutSec 10
                
                # Navigate through chain to find this Pokémon's evolution
                $findEvolution = {
                    param($chainData)
                    
                    if ($chainData.species.name -eq $pokemon.name) {
                        # This is our Pokémon - check if it evolves
                        if ($chainData.evolves_to -and $chainData.evolves_to.Count -gt 0) {
                            $nextEvolution = $chainData.evolves_to[0]
                            $evoDetails = $nextEvolution.evolution_details[0]
                            
                            if ($evoDetails.min_level) {
                                return @{
                                    method = "level"
                                    level = $evoDetails.min_level
                                    into = $nextEvolution.species.name -replace "-", "_"
                                }
                            } elseif ($evoDetails.item) {
                                return @{
                                    method = "item"
                                    item = $evoDetails.item.name -replace "-", "_"
                                    into = $nextEvolution.species.name -replace "-", "_"
                                }
                            } elseif ($evoDetails.trigger.name -eq "trade") {
                                return @{
                                    method = "trade"
                                    into = $nextEvolution.species.name -replace "-", "_"
                                }
                            }
                        }
                        return @{}
                    }
                    
                    # Check next level in evolution chain
                    if ($chainData.evolves_to -and $chainData.evolves_to.Count -gt 0) {
                        foreach ($nextChain in $chainData.evolves_to) {
                            $result = & $findEvolution $nextChain
                            if ($result.into) {
                                return $result
                            }
                        }
                    }
                    return @{}
                }
                
                $evolution = & $findEvolution $chain.chain
            }
            catch {
                Write-Host "Error getting evolution chain: $_" -ForegroundColor Yellow
            }
        }
        
        # Get gender ratio
        $genderRatio = @{
            male = if ($species.gender_rate -ge 0) { (8 - $species.gender_rate) * 12.5 } else { 0 }
            female = if ($species.gender_rate -ge 0) { $species.gender_rate * 12.5 } else { 0 }
        }
        
        # Map growth rate to Lua format
        $rawGrowthRate = $species.growth_rate.name
        $mappedGrowthRate = if ($growthRateMapping.ContainsKey($rawGrowthRate)) {
            $growthRateMapping[$rawGrowthRate]
        } else {
            $rawGrowthRate -replace "-", "_"
        }
        
        # Handle sprites - use local paths or online URLs
        $pokemonNameClean = $pokemon.name -replace "-", "_"
        if ($UseLocalSprites) {
            $spriteFront = "tiled/sprites/pokemon_front/$pokemonNameClean.png"
            $spriteBack = "tiled/sprites/pokemon_back/$pokemonNameClean.png"
        } else {
            $spriteFront = $pokemon.sprites.front_default
            $spriteBack = $pokemon.sprites.back_default
        }
        
        # Create entry matching pokemon.lua structure
        $entry = [ordered]@{
            id = $pokemon.id
            name = $pokemonNameClean
            types = @($types)
            genderRatio = [ordered]@{
                male = [double]($genderRatio.male)
                female = [double]($genderRatio.female)
            }
            catchRate = [int]$species.capture_rate
            baseExpYield = if ($pokemon.base_experience) { [int]$pokemon.base_experience } else { 50 }
            baseFriendship = [int]$species.base_happiness
            growthRate = $mappedGrowthRate
            abilities = @($abilities)
            hiddenAbility = $hiddenAbility
            baseStats = [ordered]@{
                hp = $baseStats.hp
                attack = $baseStats.attack
                defense = $baseStats.defense
                spAttack = $baseStats.spAttack
                spDefense = $baseStats.spDefense
                speed = $baseStats.speed
            }
            learnset = $learnset
            evolution = $evolution
            sprite = [ordered]@{
                front = $spriteFront
                back = $spriteBack
            }
        }
        
        $pokemonData[$pokemon.name] = $entry
    }
    catch {
        Write-Host "Error fetching Pokémon $id : $_" -ForegroundColor Red
        continue
    }
}

Write-Progress -Activity "Fetching Pokémon data" -Completed

# Convert to JSON and save (UTF8 without BOM for Lua compatibility)
$json = $pokemonData | ConvertTo-Json -Depth 10
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($outputFile, $json, $utf8NoBom)

Write-Host "`nData saved to: $outputFile" -ForegroundColor Green
Write-Host "Total Pokémon: $($pokemonData.Count)" -ForegroundColor Green
