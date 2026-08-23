function ConvertFrom-PSDrawIODiagramXml {
    <#
    .SYNOPSIS
    Parses draw.io mxfile XML text into a Core IR PSCustomObject.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $XmlText,

        [Parameter()]
        [string] $SourcePath
    )

    $doc = [System.Xml.XmlDocument]::new()
    try {
        $doc.LoadXml($XmlText)
    }
    catch {
        $name = if ($SourcePath) { $SourcePath } else { '(xml)' }
        throw ("Failed to parse draw.io XML from '{0}': {1}" -f $name, $_.Exception.Message)
    }

    $mxfile = $doc.DocumentElement
    if ($null -eq $mxfile -or $mxfile.LocalName -cne 'mxfile') {
        $name = if ($SourcePath) { $SourcePath } else { '(xml)' }
        throw ("Draw.io XML from '{0}' is missing a root mxfile element." -f $name)
    }

    $diagram = $null
    foreach ($child in @($mxfile.ChildNodes)) {
        if ($child -is [System.Xml.XmlElement] -and $child.LocalName -eq 'diagram') {
            $diagram = $child
            break
        }
    }
    if ($null -eq $diagram) {
        $name = if ($SourcePath) { $SourcePath } else { '(xml)' }
        throw ("Draw.io XML from '{0}' is missing a diagram element." -f $name)
    }

    $model = $null
    foreach ($child in @($diagram.ChildNodes)) {
        if ($child -is [System.Xml.XmlElement] -and $child.LocalName -eq 'mxGraphModel') {
            $model = $child
            break
        }
    }
    if ($null -eq $model) {
        $name = if ($SourcePath) { $SourcePath } else { '(xml)' }
        throw ("Draw.io XML from '{0}' is missing mxGraphModel." -f $name)
    }

    $root = $null
    foreach ($child in @($model.ChildNodes)) {
        if ($child -is [System.Xml.XmlElement] -and $child.LocalName -eq 'root') {
            $root = $child
            break
        }
    }
    if ($null -eq $root) {
        $name = if ($SourcePath) { $SourcePath } else { '(xml)' }
        throw ("Draw.io XML from '{0}' is missing root." -f $name)
    }

    $knownCell = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($k in @('id', 'value', 'style', 'vertex', 'edge', 'parent', 'source', 'target')) {
        $null = $knownCell.Add($k)
    }

    $readAttrs = {
        param([System.Xml.XmlElement]$el, [System.Collections.Generic.HashSet[string]]$known)
        $bag = [ordered]@{}
        if ($null -eq $el -or $null -eq $el.Attributes) { return [pscustomobject]$bag }
        foreach ($a in @($el.Attributes)) {
            if ($known -and $known.Contains($a.Name)) { continue }
            $bag[$a.Name] = $a.Value
        }
        return [pscustomobject]$bag
    }

    $allAttrs = {
        param([System.Xml.XmlElement]$el)
        $bag = [ordered]@{}
        if ($null -eq $el -or $null -eq $el.Attributes) { return [pscustomobject]$bag }
        foreach ($a in @($el.Attributes)) {
            $bag[$a.Name] = $a.Value
        }
        return [pscustomobject]$bag
    }

    # Known UserObject attrs that are not preserved custom metadata.
    $knownUo = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('label', 'link', 'id'),
        [StringComparer]::OrdinalIgnoreCase
    )

    $cells = [System.Collections.Generic.List[object]]::new()
    foreach ($n in @($root.ChildNodes)) {
        if ($n -isnot [System.Xml.XmlElement]) { continue }
        if ($n.LocalName -eq 'mxCell') {
            $cells.Add([pscustomobject]@{
                    Cell      = $n
                    Link      = $null
                    UoLabel   = $null
                    UoId      = $null
                    UoCustoms = $null
                })
        }
        elseif ($n.LocalName -eq 'UserObject' -or $n.LocalName -eq 'object') {
            $uoLink = if ($n.HasAttribute('link')) { [string]$n.GetAttribute('link') } else { $null }
            $uoLabel = if ($n.HasAttribute('label')) { [string]$n.GetAttribute('label') } else { $null }
            $uoId = if ($n.HasAttribute('id')) { [string]$n.GetAttribute('id') } else { $null }
            # Custom attrs on the wrapper normalize to the same XmlAttributes bag as bare-mxCell customs.
            $uoCustoms = & $readAttrs $n $knownUo
            foreach ($c in @($n.ChildNodes)) {
                if ($c -is [System.Xml.XmlElement] -and $c.LocalName -eq 'mxCell') {
                    $cells.Add([pscustomobject]@{
                            Cell      = $c
                            Link      = $uoLink
                            UoLabel   = $uoLabel
                            UoId      = $uoId
                            UoCustoms = $uoCustoms
                        })
                }
            }
        }
    }

    $mergeAttrBags = {
        param($primary, $secondary)
        $bag = [ordered]@{}
        foreach ($src in @($primary, $secondary)) {
            if ($null -eq $src) { continue }
            # Deterministic: sort property names when merging.
            $props = @($src.PSObject.Properties) |
                Where-Object { $null -ne $_.Name -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) } |
                Sort-Object -Property Name -CaseSensitive
            foreach ($p in $props) {
                if (-not $bag.Contains($p.Name)) {
                    $bag[$p.Name] = $p.Value
                }
            }
        }
        if ($bag.Count -eq 0) { return $null }
        return [pscustomobject]$bag
    }

    $has0 = $false
    $has1 = $false
    foreach ($entry in $cells) {
        $c = $entry.Cell
        $cid = [string]$c.GetAttribute('id')
        if ([string]::IsNullOrWhiteSpace($cid) -and -not [string]::IsNullOrWhiteSpace([string]$entry.UoId)) {
            $cid = [string]$entry.UoId
        }
        if ($cid -eq '0') { $has0 = $true }
        if ($cid -eq '1') { $has1 = $true }
    }
    if (-not $has0 -or -not $has1) {
        $name = if ($SourcePath) { $SourcePath } else { '(xml)' }
        throw ("Draw.io XML from '{0}' must contain mxCell id 0 and id 1." -f $name)
    }

    $nodes = [System.Collections.Generic.List[object]]::new()
    $edges = [System.Collections.Generic.List[object]]::new()
    $defaultStyle = 'whiteSpace=wrap;html=1;'

    foreach ($entry in $cells) {
        $c = $entry.Cell
        $cid = [string]$c.GetAttribute('id')
        # Promote wrapper id when nested mxCell omits id (schema dual-id optional).
        if ([string]::IsNullOrWhiteSpace($cid) -and -not [string]::IsNullOrWhiteSpace([string]$entry.UoId)) {
            $cid = [string]$entry.UoId
        }
        if ($cid -eq '0' -or $cid -eq '1') { continue }

        $isEdge = ([string]$c.GetAttribute('edge') -eq '1')
        $isVertex = ([string]$c.GetAttribute('vertex') -eq '1') -or (-not $isEdge)

        $geo = $null
        foreach ($ch in @($c.ChildNodes)) {
            if ($ch -is [System.Xml.XmlElement] -and $ch.LocalName -eq 'mxGeometry') {
                $geo = $ch
                break
            }
        }

        $x = $null; $y = $null; $w = $null; $h = $null; $relative = $null
        if ($null -ne $geo) {
            if ($geo.HasAttribute('x')) { $x = [double]$geo.GetAttribute('x') }
            if ($geo.HasAttribute('y')) { $y = [double]$geo.GetAttribute('y') }
            if ($geo.HasAttribute('width')) { $w = [double]$geo.GetAttribute('width') }
            if ($geo.HasAttribute('height')) { $h = [double]$geo.GetAttribute('height') }
            if ($geo.HasAttribute('relative')) { $relative = $geo.GetAttribute('relative') }
        }

        # Bare-mxCell customs and UserObject customs normalize to one XmlAttributes bag.
        $cellExtra = & $readAttrs $c $knownCell
        $extra = & $mergeAttrBags $entry.UoCustoms $cellExtra

        if ($isEdge) {
            $style = if ($c.HasAttribute('style')) { [string]$c.GetAttribute('style') } else { $null }
            $value = if ($c.HasAttribute('value')) { [string]$c.GetAttribute('value') } else { '' }
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.UoLabel)) {
                $value = [string]$entry.UoLabel
            }
            $parent = if ($c.HasAttribute('parent')) { [string]$c.GetAttribute('parent') } else { '1' }
            $meta = [ordered]@{}
            if ($null -ne $extra) {
                $meta['XmlAttributes'] = $extra
            }
            if ($parent -ne '1') { $meta['Parent'] = $parent }
            if ($null -ne $relative) { $meta['GeometryRelative'] = $relative }
            if ($c.HasAttribute('value') -or -not [string]::IsNullOrWhiteSpace([string]$entry.UoLabel)) {
                $meta['Value'] = $value
            }

            $edgeObj = [ordered]@{
                PSTypeName    = 'PS.DrawIO.IR.Edge'
                Id            = $cid
                From          = [string]$c.GetAttribute('source')
                To            = [string]$c.GetAttribute('target')
                Type          = ''
                Style         = $style
                ResolvedStyle = $style
                Aggregates    = $null
                Metadata      = [pscustomobject]$meta
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.Link)) {
                $edgeObj['Link'] = [string]$entry.Link
            }
            $edges.Add([pscustomobject]$edgeObj)
            continue
        }

        if (-not $isVertex) { continue }

        $label = [string]$c.GetAttribute('value')
        $link = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.Link)) {
            $link = [string]$entry.Link
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.UoLabel)) {
            $label = [string]$entry.UoLabel
        }

        $style = if ($c.HasAttribute('style')) {
            [string]$c.GetAttribute('style')
        }
        else {
            # Normalize missing style to Export's default so parse->emit->parse is stable.
            $defaultStyle
        }

        $parent = if ($c.HasAttribute('parent')) { [string]$c.GetAttribute('parent') } else { '1' }
        $parentId = if ($parent -eq '1' -or [string]::IsNullOrWhiteSpace($parent)) { $null } else { $parent }
        $isGroup = ($style -match '(?i)(^|;)\s*group\s*(;|$)')

        $meta = [ordered]@{}
        if ($null -ne $extra) {
            $meta['XmlAttributes'] = $extra
        }

        $nodes.Add([pscustomobject][ordered]@{
                PSTypeName = 'PS.DrawIO.IR.Node'
                Id         = $cid
                Provider   = $null
                Type       = $null
                Name       = $null
                Label      = $label
                ParentId   = $parentId
                Link       = $link
                Variant    = $null
                IsGroup    = [bool]$isGroup
                Metadata   = [pscustomobject]$meta
                Style      = $style
                X          = $x
                Y          = $y
                Width      = $w
                Height     = $h
            })
    }

    $irMeta = [ordered]@{
        MxFileAttributes  = & $allAttrs $mxfile
        DiagramAttributes = & $allAttrs $diagram
        ModelAttributes   = & $allAttrs $model
    }

    return [pscustomobject][ordered]@{
        PSTypeName   = 'PS.DrawIO.IR'
        Provider     = $null
        Nodes        = @($nodes.ToArray())
        Edges        = @($edges.ToArray())
        LayoutHints  = @()
        LinkTemplate = $null
        Metadata     = [pscustomobject]$irMeta
    }
}
