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

    $cells = [System.Collections.Generic.List[System.Xml.XmlElement]]::new()
    foreach ($n in @($root.ChildNodes)) {
        if ($n -isnot [System.Xml.XmlElement]) { continue }
        if ($n.LocalName -eq 'mxCell') {
            $cells.Add($n)
        }
        elseif ($n.LocalName -eq 'UserObject' -or $n.LocalName -eq 'object') {
            foreach ($c in @($n.ChildNodes)) {
                if ($c -is [System.Xml.XmlElement] -and $c.LocalName -eq 'mxCell') {
                    # Attach wrapper for link/label resolution.
                    $c.SetAttribute('__uoLink', [string]$n.GetAttribute('link'))
                    $c.SetAttribute('__uoLabel', [string]$n.GetAttribute('label'))
                    $uoExtra = & $readAttrs $n ([System.Collections.Generic.HashSet[string]]::new(
                            [string[]]@('label', 'link', 'id'),
                            [StringComparer]::OrdinalIgnoreCase
                        ))
                    $c.SetAttribute('__uoExtraJson', ($uoExtra | ConvertTo-Json -Compress -Depth 5))
                    $cells.Add($c)
                }
            }
        }
    }

    $has0 = $false
    $has1 = $false
    foreach ($c in $cells) {
        $cid = [string]$c.GetAttribute('id')
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

    foreach ($c in $cells) {
        $cid = [string]$c.GetAttribute('id')
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

        $extra = & $readAttrs $c $knownCell
        # Strip import-only markers from unknown bag if present.
        foreach ($marker in @('__uoLink', '__uoLabel', '__uoExtraJson')) {
            if ($null -ne $extra.PSObject.Properties[$marker]) {
                $extra.PSObject.Properties.Remove($marker)
            }
        }

        if ($isEdge) {
            $style = if ($c.HasAttribute('style')) { [string]$c.GetAttribute('style') } else { $null }
            $value = if ($c.HasAttribute('value')) { [string]$c.GetAttribute('value') } else { '' }
            $parent = if ($c.HasAttribute('parent')) { [string]$c.GetAttribute('parent') } else { '1' }
            $meta = [ordered]@{}
            if (@($extra.PSObject.Properties).Count -gt 0) {
                $meta['XmlAttributes'] = $extra
            }
            if ($parent -ne '1') { $meta['Parent'] = $parent }
            if ($null -ne $relative) { $meta['GeometryRelative'] = $relative }
            if ($c.HasAttribute('value')) { $meta['Value'] = $value }

            $edges.Add([pscustomobject][ordered]@{
                    PSTypeName    = 'PS.DrawIO.IR.Edge'
                    Id            = $cid
                    From          = [string]$c.GetAttribute('source')
                    To            = [string]$c.GetAttribute('target')
                    Type          = ''
                    Style         = $style
                    ResolvedStyle = $style
                    Aggregates    = $null
                    Metadata      = [pscustomobject]$meta
                })
            continue
        }

        if (-not $isVertex) { continue }

        $label = [string]$c.GetAttribute('value')
        $link = $null
        if ($c.HasAttribute('__uoLink') -and -not [string]::IsNullOrWhiteSpace([string]$c.GetAttribute('__uoLink'))) {
            $link = [string]$c.GetAttribute('__uoLink')
        }
        if ($c.HasAttribute('__uoLabel') -and -not [string]::IsNullOrWhiteSpace([string]$c.GetAttribute('__uoLabel'))) {
            $label = [string]$c.GetAttribute('__uoLabel')
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
        if (@($extra.PSObject.Properties).Count -gt 0) {
            $meta['XmlAttributes'] = $extra
        }
        if ($c.HasAttribute('__uoExtraJson') -and -not [string]::IsNullOrWhiteSpace([string]$c.GetAttribute('__uoExtraJson'))) {
            try {
                $uoBag = [string]$c.GetAttribute('__uoExtraJson') | ConvertFrom-Json
                if ($uoBag -and @($uoBag.PSObject.Properties).Count -gt 0) {
                    $meta['UserObjectAttributes'] = $uoBag
                }
            }
            catch {
                # __uoExtraJson is an import-only marker this function stamps via ConvertTo-Json
                # on UserObject wrappers in the same pass. It is not user diagram XML (LoadXml
                # already threw for malformed input). If ConvertFrom-Json fails, omit optional
                # UserObjectAttributes and continue the import rather than failing the diagram.
                $uoBag = $null
            }
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
