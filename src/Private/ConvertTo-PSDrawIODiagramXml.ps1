function ConvertTo-PSDrawIODiagramXml {
    <#
    .SYNOPSIS
    Builds uncompressed draw.io mxfile XML from a laid-out IR using the XML DOM.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $IR
    )

    if ($null -eq $IR) { throw 'IR is required.' }
    if ($null -eq $IR.PSObject.Properties['Nodes']) {
        throw 'IR is invalid: Nodes property is required.'
    }

    $nodes = @($IR.Nodes)
    $edges = @()
    if ($null -ne $IR.PSObject.Properties['Edges'] -and $null -ne $IR.Edges) {
        $edges = @($IR.Edges)
    }

    $nodeById = @{}
    foreach ($n in $nodes) {
        if ($null -eq $n.Id -or [string]::IsNullOrWhiteSpace([string]$n.Id)) {
            throw 'IR is invalid: node Id is required (offending node).'
        }
        $nid = [string]$n.Id
        # ADR 0001 qualifies Ids Core materializes. Imported / hand-edited files
        # may carry bare ids (e.g. hand-1); do not reject them on emit.
        if ($nodeById.ContainsKey($nid)) {
            throw ("IR is invalid: duplicate node Id '{0}'." -f $nid)
        }
        $nodeById[$nid] = $n
    }

    foreach ($e in $edges) {
        $from = [string]$e.From
        $to = [string]$e.To
        $eid = if ($null -ne $e.PSObject.Properties['Id'] -and $e.Id) { [string]$e.Id } else { '(edge)' }
        if (-not $nodeById.ContainsKey($from)) {
            throw ("IR edge rejected: From='{0}' names a node absent from the IR (offending edge Id='{1}', To='{2}')." -f $from, $eid, $to)
        }
        if (-not $nodeById.ContainsKey($to)) {
            throw ("IR edge rejected: To='{0}' names a node absent from the IR (offending edge Id='{1}', From='{2}')." -f $to, $eid, $from)
        }
    }

    $getCoord = {
        param($node, [string]$flatName, [string]$geoName)
        if ($null -ne $node.PSObject.Properties[$flatName] -and $null -ne $node.$flatName) {
            return $node.$flatName
        }
        if ($null -ne $node.PSObject.Properties['Geometry'] -and $null -ne $node.Geometry) {
            $g = $node.Geometry
            if ($null -ne $g.PSObject.Properties[$geoName] -and $null -ne $g.$geoName) {
                return $g.$geoName
            }
        }
        return $null
    }

    $isEdgeNode = {
        param($n)
        return (
            ($null -ne $n.PSObject.Properties['IsEdge'] -and [bool]$n.IsEdge) -or
            ($null -ne $n.PSObject.Properties['Edge'] -and [bool]$n.Edge)
        )
    }

    $resolveLink = {
        param($node)
        if ($null -ne $node.PSObject.Properties['Link'] -and -not [string]::IsNullOrWhiteSpace([string]$node.Link)) {
            return [string]$node.Link
        }
        $template = $null
        if ($null -ne $IR.PSObject.Properties['LinkTemplate'] -and $null -ne $IR.LinkTemplate) {
            $template = [string]$IR.LinkTemplate
        }
        if ([string]::IsNullOrWhiteSpace($template)) { return $null }

        $path = ''
        $line = ''
        if ($null -ne $node.PSObject.Properties['Metadata'] -and $null -ne $node.Metadata) {
            $m = $node.Metadata
            if ($null -ne $m.PSObject.Properties['Path'] -and $null -ne $m.Path) { $path = [string]$m.Path }
            if ($null -ne $m.PSObject.Properties['Line'] -and $null -ne $m.Line) { $line = [string]$m.Line }
        }
        if ($null -ne $node.PSObject.Properties['Path'] -and $null -ne $node.Path) { $path = [string]$node.Path }
        if ($null -ne $node.PSObject.Properties['Line'] -and $null -ne $node.Line) { $line = [string]$node.Line }

        return ($template -replace '\{Path\}', $path -replace '\{Line\}', $line)
    }

    $buildStyle = {
        param($node)
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($propName in @('ResolvedStyle', 'Style', 'ShapeStyle')) {
            if ($null -ne $node.PSObject.Properties[$propName] -and -not [string]::IsNullOrWhiteSpace([string]$node.$propName)) {
                $parts.Add(([string]$node.$propName).Trim().TrimEnd(';'))
                break
            }
        }

        $shape = $null
        if ($null -ne $node.PSObject.Properties['Shape'] -and $node.Shape) {
            $shape = [string]$node.Shape
        }
        elseif ($null -ne $node.PSObject.Properties['Metadata'] -and $null -ne $node.Metadata -and
            $null -ne $node.Metadata.PSObject.Properties['Shape'] -and $node.Metadata.Shape) {
            $shape = [string]$node.Metadata.Shape
        }

        if ($shape) {
            $joined = ($parts -join ';')
            if ($joined -notmatch '(?i)\bshape=') {
                $parts.Add(('shape={0}' -f $shape))
            }
            if ($shape -cne 'rectangle' -and $shape -cne 'rect' -and $joined -notmatch '(?i)\bperimeter=') {
                $parts.Add(('perimeter={0}Perimeter' -f $shape))
            }
        }

        if ($null -ne $node.PSObject.Properties['IsGroup'] -and [bool]$node.IsGroup) {
            $joined = ($parts -join ';')
            if ($joined -notmatch '(?i)(^|;)\s*group\s*(;|$)') {
                $parts.Add('group')
            }
        }

        if ($parts.Count -eq 0) {
            return 'whiteSpace=wrap;html=1;'
        }
        $style = ($parts -join ';')
        if (-not $style.EndsWith(';')) { $style += ';' }
        return $style
    }

    $applyAttrBag = {
        param([System.Xml.XmlElement]$el, $bag)
        if ($null -eq $bag) { return }
        # Deterministic order: sort by name so golden text comparison is stable.
        $props = @($bag.PSObject.Properties) |
            Where-Object { $null -ne $_.Name -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) } |
            Sort-Object -Property Name -CaseSensitive
        foreach ($p in $props) {
            if ($el.HasAttribute($p.Name)) { continue }
            $null = $el.SetAttribute([string]$p.Name, [string]$p.Value)
        }
    }

    $hasPreservedAttrs = {
        param($meta)
        if ($null -eq $meta) { return $false }
        if ($null -ne $meta.PSObject.Properties['XmlAttributes'] -and $null -ne $meta.XmlAttributes) {
            if (@($meta.XmlAttributes.PSObject.Properties).Count -gt 0) { return $true }
        }
        if ($null -ne $meta.PSObject.Properties['UserObjectAttributes'] -and $null -ne $meta.UserObjectAttributes) {
            if (@($meta.UserObjectAttributes.PSObject.Properties).Count -gt 0) { return $true }
        }
        return $false
    }

    $doc = [System.Xml.XmlDocument]::new()
    $null = $doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'UTF-8', $null))

    $mxfile = $doc.CreateElement('mxfile')
    $null = $doc.AppendChild($mxfile)

    $diagram = $doc.CreateElement('diagram')
    $null = $mxfile.AppendChild($diagram)

    $model = $doc.CreateElement('mxGraphModel')
    $null = $diagram.AppendChild($model)

    $null = $mxfile.SetAttribute('host', 'app.diagrams.net')
    $null = $diagram.SetAttribute('id', 'page-1')
    $null = $diagram.SetAttribute('name', 'Page-1')

    if ($null -ne $IR.PSObject.Properties['Metadata'] -and $null -ne $IR.Metadata) {
        $im = $IR.Metadata
        if ($null -ne $im.PSObject.Properties['MxFileAttributes'] -and $null -ne $im.MxFileAttributes) {
            foreach ($p in @($im.MxFileAttributes.PSObject.Properties)) {
                $null = $mxfile.SetAttribute([string]$p.Name, [string]$p.Value)
            }
        }
        if ($null -ne $im.PSObject.Properties['DiagramAttributes'] -and $null -ne $im.DiagramAttributes) {
            foreach ($p in @($im.DiagramAttributes.PSObject.Properties)) {
                $null = $diagram.SetAttribute([string]$p.Name, [string]$p.Value)
            }
        }
        if ($null -ne $im.PSObject.Properties['ModelAttributes'] -and $null -ne $im.ModelAttributes) {
            foreach ($p in @($im.ModelAttributes.PSObject.Properties)) {
                $null = $model.SetAttribute([string]$p.Name, [string]$p.Value)
            }
        }
    }

    $root = $doc.CreateElement('root')
    $null = $model.AppendChild($root)

    $cell0 = $doc.CreateElement('mxCell')
    $null = $cell0.SetAttribute('id', '0')
    $null = $root.AppendChild($cell0)

    $cell1 = $doc.CreateElement('mxCell')
    $null = $cell1.SetAttribute('id', '1')
    $null = $cell1.SetAttribute('parent', '0')
    $null = $root.AppendChild($cell1)

    $usedIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $null = $usedIds.Add('0')
    $null = $usedIds.Add('1')

    $appendGeometry = {
        param([System.Xml.XmlElement]$cell, $node, [switch]$EdgeRelative)
        if ($EdgeRelative) {
            $geo = $doc.CreateElement('mxGeometry')
            $null = $geo.SetAttribute('relative', '1')
            $null = $geo.SetAttribute('as', 'geometry')
            $null = $cell.AppendChild($geo)
            return
        }

        $x = & $getCoord $node 'X' 'X'
        $y = & $getCoord $node 'Y' 'Y'
        $w = & $getCoord $node 'Width' 'Width'
        $h = & $getCoord $node 'Height' 'Height'
        if ($null -eq $x -and $null -eq $y -and $null -eq $w -and $null -eq $h) {
            return
        }
        $geo = $doc.CreateElement('mxGeometry')
        if ($null -ne $x) { $null = $geo.SetAttribute('x', [string]([double]$x)) }
        if ($null -ne $y) { $null = $geo.SetAttribute('y', [string]([double]$y)) }
        if ($null -ne $w) { $null = $geo.SetAttribute('width', [string]([double]$w)) }
        if ($null -ne $h) { $null = $geo.SetAttribute('height', [string]([double]$h)) }
        $null = $geo.SetAttribute('as', 'geometry')
        $null = $cell.AppendChild($geo)
    }

    foreach ($n in $nodes) {
        if (& $isEdgeNode $n) { continue }

        $id = [string]$n.Id
        if ($id -eq '0' -or $id -eq '1') {
            throw ("IR node Id '{0}' collides with reserved root cell id." -f $id)
        }
        if (-not $usedIds.Add($id)) {
            throw ("Duplicate cell id '{0}'." -f $id)
        }

        $label = if ($null -ne $n.PSObject.Properties['Label'] -and $null -ne $n.Label) {
            [string]$n.Label
        }
        elseif ($null -ne $n.PSObject.Properties['Name'] -and $null -ne $n.Name) {
            [string]$n.Name
        }
        else {
            $id
        }

        $parent = '1'
        if ($null -ne $n.PSObject.Properties['ParentId'] -and -not [string]::IsNullOrWhiteSpace([string]$n.ParentId)) {
            $parent = [string]$n.ParentId
        }

        $style = & $buildStyle $n
        $link = & $resolveLink $n
        $meta = $null
        if ($null -ne $n.PSObject.Properties['Metadata'] -and $null -ne $n.Metadata) {
            $meta = $n.Metadata
        }
        $wrap = ($link -or (& $hasPreservedAttrs $meta))

        $cell = $doc.CreateElement('mxCell')
        $null = $cell.SetAttribute('id', $id)
        if (-not $wrap) {
            # Bare mxCell carries the label as value. UserObject wrappers use label= instead.
            $null = $cell.SetAttribute('value', $label)
        }
        $null = $cell.SetAttribute('style', $style)
        $null = $cell.SetAttribute('vertex', '1')
        $null = $cell.SetAttribute('parent', $parent)
        & $appendGeometry $cell $n

        if ($wrap) {
            # ADR 0006 Option A: link and/or preserved attrs live on UserObject with required id.
            # Nested mxCell keeps its own id (schema permits; uniqueness tests assert mxCell ids).
            $uo = $doc.CreateElement('UserObject')
            $null = $uo.SetAttribute('id', $id)
            $null = $uo.SetAttribute('label', $label)
            if ($link) {
                $null = $uo.SetAttribute('link', $link)
            }
            if ($null -ne $meta) {
                if ($null -ne $meta.PSObject.Properties['XmlAttributes'] -and $null -ne $meta.XmlAttributes) {
                    & $applyAttrBag $uo $meta.XmlAttributes
                }
                if ($null -ne $meta.PSObject.Properties['UserObjectAttributes'] -and $null -ne $meta.UserObjectAttributes) {
                    & $applyAttrBag $uo $meta.UserObjectAttributes
                }
            }
            $null = $uo.AppendChild($cell)
            $null = $root.AppendChild($uo)
        }
        else {
            $null = $root.AppendChild($cell)
        }
    }

    $edgeIndex = 0
    foreach ($e in $edges) {
        $eid = if ($null -ne $e.PSObject.Properties['Id'] -and -not [string]::IsNullOrWhiteSpace([string]$e.Id)) {
            [string]$e.Id
        }
        else {
            'edge-{0}' -f $edgeIndex
        }
        if ($eid -eq '0' -or $eid -eq '1' -or -not $usedIds.Add($eid)) {
            $eid = 'edge-{0}-{1}' -f $edgeIndex, ([guid]::NewGuid().ToString('N').Substring(0, 8))
            $null = $usedIds.Add($eid)
        }

        $style = 'endArrow=classic;html=1;rounded=0;'
        if ($null -ne $e.PSObject.Properties['ResolvedStyle'] -and -not [string]::IsNullOrWhiteSpace([string]$e.ResolvedStyle)) {
            $style = [string]$e.ResolvedStyle
            if (-not $style.EndsWith(';')) { $style += ';' }
        }
        elseif ($null -ne $e.PSObject.Properties['Style'] -and -not [string]::IsNullOrWhiteSpace([string]$e.Style)) {
            $style = [string]$e.Style
            if (-not $style.EndsWith(';')) { $style += ';' }
        }

        $parent = '1'
        if ($null -ne $e.PSObject.Properties['Metadata'] -and $null -ne $e.Metadata -and
            $null -ne $e.Metadata.PSObject.Properties['Parent'] -and -not [string]::IsNullOrWhiteSpace([string]$e.Metadata.Parent)) {
            $parent = [string]$e.Metadata.Parent
        }

        $value = ''
        $eMeta = $null
        if ($null -ne $e.PSObject.Properties['Metadata'] -and $null -ne $e.Metadata) {
            $eMeta = $e.Metadata
            if ($null -ne $eMeta.PSObject.Properties['Value']) {
                $value = [string]$eMeta.Value
            }
        }
        $eLink = $null
        if ($null -ne $e.PSObject.Properties['Link'] -and -not [string]::IsNullOrWhiteSpace([string]$e.Link)) {
            $eLink = [string]$e.Link
        }
        $eWrap = ($eLink -or (& $hasPreservedAttrs $eMeta))

        $cell = $doc.CreateElement('mxCell')
        $null = $cell.SetAttribute('id', $eid)
        if (-not $eWrap) {
            $null = $cell.SetAttribute('value', $value)
        }
        $null = $cell.SetAttribute('style', $style)
        $null = $cell.SetAttribute('edge', '1')
        $null = $cell.SetAttribute('parent', $parent)
        $null = $cell.SetAttribute('source', [string]$e.From)
        $null = $cell.SetAttribute('target', [string]$e.To)
        & $appendGeometry $cell $e -EdgeRelative

        if ($eWrap) {
            $uo = $doc.CreateElement('UserObject')
            $null = $uo.SetAttribute('id', $eid)
            $null = $uo.SetAttribute('label', $value)
            if ($eLink) {
                $null = $uo.SetAttribute('link', $eLink)
            }
            if ($null -ne $eMeta) {
                if ($null -ne $eMeta.PSObject.Properties['XmlAttributes'] -and $null -ne $eMeta.XmlAttributes) {
                    & $applyAttrBag $uo $eMeta.XmlAttributes
                }
                if ($null -ne $eMeta.PSObject.Properties['UserObjectAttributes'] -and $null -ne $eMeta.UserObjectAttributes) {
                    & $applyAttrBag $uo $eMeta.UserObjectAttributes
                }
            }
            $null = $uo.AppendChild($cell)
            $null = $root.AppendChild($uo)
        }
        else {
            $null = $root.AppendChild($cell)
        }
        $edgeIndex++
    }

    return $doc.OuterXml
}
