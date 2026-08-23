function Invoke-PSDrawIOBuiltinLayout {
    <#
    .SYNOPSIS
    Built-in deterministic grid/stack layout strategy for IR vertices.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $IR
    )

    # Geometry constants live only in the layout pass (CORE.md 5 / 9).
    $defaultWidth = 120
    $defaultHeight = 40
    $hGap = 40
    $vGap = 24
    $originX = 40
    $originY = 40
    $groupPad = 20
    $columns = 4

    $nodes = @($IR.Nodes)
    $byId = @{}
    foreach ($n in $nodes) {
        if ($null -ne $n.Id) { $byId[[string]$n.Id] = $n }
    }

    $isVertex = {
        param($n)
        -not (
            ($null -ne $n.PSObject.Properties['IsEdge'] -and [bool]$n.IsEdge) -or
            ($null -ne $n.PSObject.Properties['Edge'] -and [bool]$n.Edge)
        )
    }

    $vertices = @($nodes | Where-Object { & $isVertex $_ })

    # Optional Stack hint: order listed targets first (stable among themselves).
    $ordered = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($hint in @($IR.LayoutHints)) {
        $kind = if ($null -ne $hint.PSObject.Properties['Kind']) { [string]$hint.Kind } else { $null }
        if ($kind -cne 'Stack') { continue }
        foreach ($target in @($hint.Targets)) {
            $tid = [string]$target
            if ($byId.ContainsKey($tid) -and $seen.Add($tid)) {
                $ordered.Add($byId[$tid])
            }
        }
    }
    foreach ($v in $vertices) {
        $vid = [string]$v.Id
        if ($seen.Add($vid)) { $ordered.Add($v) }
    }

    # Partition: top-level vs children of a group parent present in the IR.
    $childrenByParent = @{}
    $topLevel = [System.Collections.Generic.List[object]]::new()
    foreach ($v in $ordered) {
        $parentId = $null
        if ($null -ne $v.PSObject.Properties['ParentId'] -and -not [string]::IsNullOrWhiteSpace([string]$v.ParentId)) {
            $parentId = [string]$v.ParentId
        }
        if ($parentId -and $byId.ContainsKey($parentId)) {
            if (-not $childrenByParent.ContainsKey($parentId)) {
                $childrenByParent[$parentId] = [System.Collections.Generic.List[object]]::new()
            }
            $childrenByParent[$parentId].Add($v)
        }
        else {
            $topLevel.Add($v)
        }
    }

    $setGeom = {
        param($node, $x, $y, $w, $h)
        $node | Add-Member -NotePropertyName X -NotePropertyValue ([double]$x) -Force
        $node | Add-Member -NotePropertyName Y -NotePropertyValue ([double]$y) -Force
        $node | Add-Member -NotePropertyName Width -NotePropertyValue ([double]$w) -Force
        $node | Add-Member -NotePropertyName Height -NotePropertyValue ([double]$h) -Force
    }

    $placeRow = {
        param([System.Collections.Generic.List[object]]$items, [double]$baseX, [double]$baseY)
        $i = 0
        foreach ($item in $items) {
            $col = $i % $columns
            $row = [int][Math]::Floor($i / $columns)
            $x = $baseX + ($col * ($defaultWidth + $hGap))
            $y = $baseY + ($row * ($defaultHeight + $vGap))
            & $setGeom $item $x $y $defaultWidth $defaultHeight
            $i++
        }
        if ($items.Count -eq 0) { return 0.0 }
        $rows = [Math]::Ceiling($items.Count / [double]$columns)
        return [double]($rows * $defaultHeight + [Math]::Max(0, $rows - 1) * $vGap)
    }

    # Place children first (relative to parent origin), then size groups, then top-level.
    foreach ($parentId in @($childrenByParent.Keys)) {
        $kids = $childrenByParent[$parentId]
        $null = & $placeRow $kids $groupPad $groupPad
    }

    foreach ($v in $topLevel) {
        $vid = [string]$v.Id
        if ($childrenByParent.ContainsKey($vid)) {
            $kids = $childrenByParent[$vid]
            $maxRight = 0.0
            $maxBottom = 0.0
            foreach ($k in $kids) {
                $right = [double]$k.X + [double]$k.Width
                $bottom = [double]$k.Y + [double]$k.Height
                if ($right -gt $maxRight) { $maxRight = $right }
                if ($bottom -gt $maxBottom) { $maxBottom = $bottom }
            }
            $gw = [Math]::Max($defaultWidth, $maxRight + $groupPad)
            $gh = [Math]::Max($defaultHeight, $maxBottom + $groupPad)
            $v | Add-Member -NotePropertyName Width -NotePropertyValue ([double]$gw) -Force
            $v | Add-Member -NotePropertyName Height -NotePropertyValue ([double]$gh) -Force
            # X/Y assigned in top-level pass below
            $v | Add-Member -NotePropertyName _LayoutIsGroupBox -NotePropertyValue $true -Force
        }
    }

    $i = 0
    foreach ($v in $topLevel) {
        $col = $i % $columns
        $row = [int][Math]::Floor($i / $columns)
        $x = $originX + ($col * ($defaultWidth + $hGap))
        $y = $originY + ($row * ($defaultHeight + $vGap))
        # Groups may be wider than default; advance using default cell pitch for determinism.
        $w = if ($null -ne $v.PSObject.Properties['Width'] -and $null -ne $v.Width) { [double]$v.Width } else { [double]$defaultWidth }
        $h = if ($null -ne $v.PSObject.Properties['Height'] -and $null -ne $v.Height) { [double]$v.Height } else { [double]$defaultHeight }
        & $setGeom $v $x $y $w $h
        if ($null -ne $v.PSObject.Properties['_LayoutIsGroupBox']) {
            $v.PSObject.Properties.Remove('_LayoutIsGroupBox')
        }
        $i++
    }

    return $IR
}
