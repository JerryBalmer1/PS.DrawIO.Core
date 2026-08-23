function Test-PSDrawIODiagramSchema {
    <#
    .SYNOPSIS
    Validates draw.io XML against the vendored mxfile.xsd and structural root cells.

    .DESCRIPTION
    Loads Schema/mxfile.xsd via XmlSchemaSet (in-process, no network) and validates
    -Content. Also enforces structural root cells id="0" and id="1" parent="0"
    required by CORE.md §7/§8. Failures are terminating errors that name the
    element/attribute and the schema rule (message includes the word "schema").

    .PARAMETER Content
    Uncompressed draw.io XML text.

    .EXAMPLE
    $xml = @'
    <mxfile host="app.diagrams.net"><diagram id="p" name="Page-1"><mxGraphModel><root>
    <mxCell id="0"/><mxCell id="1" parent="0"/>
    </root></mxGraphModel></diagram></mxfile>
    '@
    Test-PSDrawIODiagramSchema -Content $xml
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Content
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw 'Diagram schema validation failed: Content is empty.'
    }

    $xsdPath = Resolve-PSDrawIOSchemaPath
    $schemaSet = [System.Xml.Schema.XmlSchemaSet]::new()
    try {
        $null = $schemaSet.Add('', $xsdPath)
        $schemaSet.Compile()
    }
    catch {
        throw ("Diagram schema validation failed: could not load schema from '{0}': {1}" -f $xsdPath, $_.Exception.Message)
    }

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.ValidationType = [System.Xml.ValidationType]::Schema
    $settings.Schemas = $schemaSet
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit

    $validationErrors = [System.Collections.Generic.List[string]]::new()
    $handler = [System.Xml.Schema.ValidationEventHandler] {
        param($eventSender, $validationEvent)
        $null = $eventSender
        $msg = $validationEvent.Message
        $ex = $validationEvent.Exception
        if ($null -ne $ex -and $ex.LineNumber -gt 0) {
            $msg = '{0} (line {1}, position {2})' -f $msg, $ex.LineNumber, $ex.LinePosition
        }
        $validationErrors.Add($msg)
    }
    $settings.add_ValidationEventHandler($handler)

    $stringReader = $null
    $reader = $null
    try {
        $stringReader = [System.IO.StringReader]::new($Content)
        $reader = [System.Xml.XmlReader]::Create($stringReader, $settings)
        while ($reader.Read()) { }
    }
    catch [System.Xml.XmlException] {
        throw ("Diagram schema validation failed: XML is not well-formed — {0}" -f $_.Exception.Message)
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stringReader) { $stringReader.Dispose() }
    }

    if ($validationErrors.Count -gt 0) {
        $detail = ($validationErrors | Select-Object -First 8) -join '; '
        throw ("Diagram schema validation failed: {0}" -f $detail)
    }

    Test-PSDrawIODiagramStructuralRoot -Content $Content
    return $true
}
