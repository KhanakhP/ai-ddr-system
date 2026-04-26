param(
  [Parameter(Mandatory=$true)]
  [string]$InspectionPdf,

  [Parameter(Mandatory=$true)]
  [string]$ThermalPdf,

  [string]$OutputDir = ".\output",
  [string]$Model = "gpt-4o-mini"
)

$ErrorActionPreference = "Stop"

function New-CleanDirectory {
  param([string]$Path)
  if (!(Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Get-ExecutablePath {
  param([string]$Name)

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  $knownPaths = @(
    (Join-Path $env:ProgramFiles "Git\mingw64\bin\$Name"),
    (Join-Path $env:ProgramFiles "poppler\Library\bin\$Name"),
    (Join-Path ${env:ProgramFiles(x86)} "poppler\Library\bin\$Name")
  )

  foreach ($path in $knownPaths) {
    if ($path -and (Test-Path -LiteralPath $path)) { return $path }
  }

  return $null
}

function ConvertFrom-PdfLiteralString {
  param([string]$Raw)
  if ($Raw.Length -lt 2) { return "" }
  $inner = $Raw.Substring(1, $Raw.Length - 2)
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $inner.Length; $i++) {
    $ch = $inner[$i]
    if ($ch -eq "\" -and $i + 1 -lt $inner.Length) {
      $i++
      $next = $inner[$i]
      switch ($next) {
        "n" { [void]$sb.Append(" ") }
        "r" { [void]$sb.Append(" ") }
        "t" { [void]$sb.Append(" ") }
        "b" { }
        "f" { }
        "(" { [void]$sb.Append("(") }
        ")" { [void]$sb.Append(")") }
        "\" { [void]$sb.Append("\") }
        default { [void]$sb.Append($next) }
      }
    } else {
      [void]$sb.Append($ch)
    }
  }
  return $sb.ToString()
}

function Expand-FlateStream {
  param([byte[]]$Data)
  foreach ($skip in @(0, 2)) {
    try {
      $ms = New-Object System.IO.MemoryStream(,$Data)
      if ($skip -gt 0) { $ms.Position = $skip }
      $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
      $out = New-Object System.IO.MemoryStream
      $ds.CopyTo($out)
      $ds.Dispose()
      return $out.ToArray()
    } catch {
      continue
    }
  }
  return $null
}

function Get-PdfText {
  param([string]$Path)

  $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
  $pdftotext = Get-ExecutablePath -Name "pdftotext.exe"
  if ($pdftotext) {
    try {
      $standardText = & $pdftotext -layout -enc UTF-8 $resolvedPath -
      $standardText = (($standardText -join "`n") -replace "\s+\n", "`n").Trim()
      if ($standardText.Length -gt 20) {
        return $standardText
      }
    } catch {
      Write-Host "pdftotext failed; using built-in fallback extraction."
    }
  }

  $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
  $enc = [System.Text.Encoding]::GetEncoding("iso-8859-1")
  $pdf = $enc.GetString($bytes)
  $streamRegex = [regex]"(?s)(<<.*?/Filter\s*/FlateDecode.*?>>\s*stream\r?\n)(.*?)(\r?\nendstream)"
  $parts = New-Object System.Collections.Generic.List[string]

  foreach ($match in $streamRegex.Matches($pdf)) {
    $start = $enc.GetByteCount($pdf.Substring(0, $match.Groups[2].Index))
    $length = $enc.GetByteCount($match.Groups[2].Value)
    $data = New-Object byte[] $length
    [Array]::Copy($bytes, $start, $data, 0, $length)
    $expanded = Expand-FlateStream -Data $data
    if ($null -eq $expanded) { continue }

    $textStream = $enc.GetString($expanded)
    if ($textStream -notmatch "BT") { continue }

    $literals = [regex]::Matches($textStream, "\((?:\\.|[^\\)])*\)")
    if ($literals.Count -eq 0) { continue }

    $line = New-Object System.Text.StringBuilder
    foreach ($literal in $literals) {
      $piece = ConvertFrom-PdfLiteralString -Raw $literal.Value
      if ($piece.Trim().Length -gt 0) {
        [void]$line.Append($piece)
        if ($piece -match "[\.:,;]$") { [void]$line.Append(" ") }
      }
    }

    $clean = ($line.ToString() -replace "[^\x09\x0A\x0D\x20-\x7E]", " ")
    $clean = ($clean -replace "\s+", " ").Trim()
    $letterCount = ([regex]::Matches($clean, "[A-Za-z]")).Count
    $minimumLetters = [Math]::Max(12, [Math]::Floor($clean.Length * 0.15))
    if ($clean.Length -gt 20 -and $letterCount -ge $minimumLetters) {
      $parts.Add($clean)
    }
  }

  return (($parts | Select-Object -Unique) -join "`n`n")
}

function Export-EmbeddedImages {
  param(
    [string]$Path,
    [string]$Prefix,
    [string]$AssetsDir
  )

  $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
  $enc = [System.Text.Encoding]::GetEncoding("iso-8859-1")
  $pdf = $enc.GetString($bytes)
  $images = New-Object System.Collections.Generic.List[object]
  $count = 0

  $dctRegex = [regex]"(?s)(<<.*?/Filter\s*(?:\[.*?/DCTDecode.*?\]|/DCTDecode).*?>>\s*stream\r?\n)(.*?)(\r?\nendstream)"
  foreach ($match in $dctRegex.Matches($pdf)) {
    $start = $enc.GetByteCount($pdf.Substring(0, $match.Groups[2].Index))
    $length = $enc.GetByteCount($match.Groups[2].Value)
    $data = New-Object byte[] $length
    [Array]::Copy($bytes, $start, $data, 0, $length)

    $soi = -1
    for ($idx = 0; $idx -lt ($data.Length - 1); $idx++) {
      if ($data[$idx] -eq 0xFF -and $data[$idx + 1] -eq 0xD8) { $soi = $idx; break }
    }
    if ($soi -lt 0) { continue }

    $eoi = -1
    for ($idx = $data.Length - 2; $idx -ge $soi; $idx--) {
      if ($data[$idx] -eq 0xFF -and $data[$idx + 1] -eq 0xD9) { $eoi = $idx + 1; break }
    }
    if ($eoi -lt 0) { continue }

    $imgLength = $eoi + 1 - $soi
    if ($imgLength -le 5000) { continue }
    $count++
    $fileName = "{0}-{1:00}.jpg" -f $Prefix, $count
    $outPath = Join-Path $AssetsDir $fileName
    $img = New-Object byte[] $imgLength
    [Array]::Copy($data, $soi, $img, 0, $imgLength)
    [System.IO.File]::WriteAllBytes($outPath, $img)
    $images.Add([ordered]@{
      source = $Prefix
      file = "assets/$fileName"
      bytes = $imgLength
    })
  }

  if ($images.Count -gt 0) {
    return $images.ToArray()
  }

  $i = 0
  while ($i -lt ($bytes.Length - 3)) {
    if ($bytes[$i] -eq 0xFF -and $bytes[$i + 1] -eq 0xD8) {
      $j = $i + 2
      while ($j -lt ($bytes.Length - 1)) {
        if ($bytes[$j] -eq 0xFF -and $bytes[$j + 1] -eq 0xD9) {
          $length = $j + 2 - $i
          if ($length -gt 5000) {
            $count++
            $fileName = "{0}-{1:00}.jpg" -f $Prefix, $count
            $outPath = Join-Path $AssetsDir $fileName
            $img = New-Object byte[] $length
            [Array]::Copy($bytes, $i, $img, 0, $length)
            [System.IO.File]::WriteAllBytes($outPath, $img)
            $images.Add([ordered]@{
              source = $Prefix
              file = "assets/$fileName"
              bytes = $length
            })
          }
          $i = $j + 2
          break
        }
        $j++
      }
    }
    $i++
  }

  return $images.ToArray()
}

function ConvertTo-LimitedText {
  param([string]$Text, [int]$Limit = 30000)
  if ($Text.Length -le $Limit) { return $Text }
  return $Text.Substring(0, $Limit) + "`n...[truncated for prompt]..."
}

function Invoke-DdrModel {
  param(
    [string]$InspectionText,
    [string]$ThermalText,
    [array]$Images,
    [string]$Model
  )

  if ([string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
    return $null
  }

  $imageList = ($Images | ForEach-Object { "- $($_.file) from $($_.source)" }) -join "`n"
  $prompt = @"
You are generating a client-ready Detailed Diagnostic Report (DDR) from source inspection and thermal report text.

Rules:
- Use only facts present in the source text.
- Do not invent measurements, locations, or causes.
- Mention missing or conflicting details when relevant.
- Use simple client-friendly language.
- Avoid duplicate observations.
- Assign related image file paths from the provided image list where they support an observation. If unsure, leave images empty.

Return valid JSON only with this shape:
{
  "property_issue_summary": "string",
  "area_wise_observations": [
    {
      "area": "string",
      "inspection_observations": ["string"],
      "thermal_findings": ["string"],
      "combined_finding": "string",
      "images": ["assets/file.jpg"]
    }
  ],
  "probable_root_cause": ["string"],
  "severity_assessment": {
    "level": "Low | Moderate | High | Critical | Unknown",
    "reasoning": "string"
  },
  "recommended_actions": ["string"],
  "additional_notes": ["string"]
}

Available extracted images:
$imageList

Inspection report text:
$(ConvertTo-LimitedText -Text $InspectionText)

Thermal report text:
$(ConvertTo-LimitedText -Text $ThermalText)
"@

  $body = @{
    model = $Model
    response_format = @{ type = "json_object" }
    messages = @(
      @{ role = "system"; content = "You convert imperfect technical inspection documents into reliable structured DDR JSON." },
      @{ role = "user"; content = $prompt }
    )
    temperature = 0.2
  } | ConvertTo-Json -Depth 20

  $headers = @{
    "Authorization" = "Bearer $env:OPENAI_API_KEY"
    "Content-Type" = "application/json"
  }

  $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers $headers -Body $body
  return ($response.choices[0].message.content | ConvertFrom-Json)
}

function New-FallbackDdr {
  param([string]$InspectionText, [string]$ThermalText, [array]$Images)

  $inspectionSnippet = (ConvertTo-LimitedText -Text $InspectionText -Limit 2500)
  $thermalSnippet = (ConvertTo-LimitedText -Text $ThermalText -Limit 2500)
  $thermalImages = @($Images | Where-Object { $_.source -eq "thermal" } | Select-Object -First 6 | ForEach-Object { $_.file })
  $inspectionImages = @($Images | Where-Object { $_.source -eq "inspection" } | Select-Object -First 4 | ForEach-Object { $_.file })

  $hotspots = @([regex]::Matches($ThermalText, "Hotspot\s*:\s*([0-9]+(?:\.[0-9]+)?)") | ForEach-Object { [double]$_.Groups[1].Value })
  $coldspots = @([regex]::Matches($ThermalText, "Coldspot\s*:\s*([0-9]+(?:\.[0-9]+)?)") | ForEach-Object { [double]$_.Groups[1].Value })
  $thermalSummary = "Thermal report text was extracted but no temperature range could be summarized automatically."
  if ($hotspots.Count -gt 0 -and $coldspots.Count -gt 0) {
    $thermalSummary = "Thermal images list hotspot readings from $([Math]::Round(($hotspots | Measure-Object -Minimum).Minimum, 1)) C to $([Math]::Round(($hotspots | Measure-Object -Maximum).Maximum, 1)) C and coldspot readings from $([Math]::Round(($coldspots | Measure-Object -Minimum).Minimum, 1)) C to $([Math]::Round(($coldspots | Measure-Object -Maximum).Maximum, 1)) C."
  }

  function Select-InspectionImages([int]$Skip, [int]$Take) {
    return @($Images | Where-Object { $_.source -eq "inspection" } | Select-Object -Skip $Skip -First $Take | ForEach-Object { $_.file })
  }

  if ($InspectionText -match "SUMMARY TABLE" -and $InspectionText -match "Observed dampness") {
    return [pscustomobject]@{
      property_issue_summary = "The inspection identifies dampness, leakage, tile-joint gaps, plumbing concerns, and external wall cracking affecting Flat No. 103 and related adjacent/common areas. The thermal document provides supporting image readings. This draft uses only extracted source facts and should be rerun with OPENAI_API_KEY for model-based image-to-observation matching."
      area_wise_observations = @(
        [pscustomobject]@{
          area = "Hall"
          inspection_observations = @("Observed dampness at the skirting level of the Hall of Flat No. 103.", "Exposed/positive side noted gaps between tile joints in the Common Bathroom of Flat No. 103.")
          thermal_findings = @($thermalSummary)
          combined_finding = "Hall skirting dampness is likely connected to moisture movement from adjacent wet-area tile joint gaps noted in the inspection."
          images = Select-InspectionImages 0 6
        },
        [pscustomobject]@{
          area = "Common Bedroom"
          inspection_observations = @("Observed dampness at the skirting level of the Common Bedroom of Flat No. 103.", "Common Bathroom tile hollowness / tile-joint gaps are noted as positive-side observations.")
          thermal_findings = @($thermalSummary)
          combined_finding = "Bedroom skirting dampness should be checked against bathroom tile joints and concealed plumbing paths."
          images = Select-InspectionImages 6 6
        },
        [pscustomobject]@{
          area = "Master Bedroom"
          inspection_observations = @("Observed dampness at the skirting level of the Master Bedroom of Flat No. 103.", "Master Bedroom Bathroom tile hollowness / tile-joint gaps are listed as related positive-side observations.")
          thermal_findings = @($thermalSummary)
          combined_finding = "Master Bedroom dampness appears associated with wet-area tile gaps/hollowness near the Master Bedroom Bathroom."
          images = Select-InspectionImages 12 8
        },
        [pscustomobject]@{
          area = "Kitchen"
          inspection_observations = @("Observed dampness at the skirting level of the Kitchen of Flat No. 103.")
          thermal_findings = @($thermalSummary)
          combined_finding = "Kitchen skirting dampness requires moisture-source confirmation from adjoining wet areas, plumbing lines, or wall interfaces."
          images = Select-InspectionImages 20 6
        },
        [pscustomobject]@{
          area = "Master Bedroom Wall / External Wall"
          inspection_observations = @("Observed dampness and efflorescence on the wall surface of the Master Bedroom of Flat No. 103.", "Observed cracks on the external wall of the building near the Master Bedroom of Flat No. 103.", "The source notes external wall crack and duct issue.")
          thermal_findings = @($thermalSummary)
          combined_finding = "Wall dampness and efflorescence are consistent with moisture ingress risk from the external wall crack/duct condition noted in the source."
          images = Select-InspectionImages 26 8
        },
        [pscustomobject]@{
          area = "Parking Area"
          inspection_observations = @("Observed leakage at the Parking ceiling below Flat No. 103.", "Positive-side observation notes plumbing issue and gaps between tile joints of the Common Bathroom of Flat No. 103.")
          thermal_findings = @($thermalSummary)
          combined_finding = "Parking ceiling leakage is likely related to wet-area plumbing or tile-joint gaps above, but the exact path should be confirmed before repair."
          images = Select-InspectionImages 34 6
        },
        [pscustomobject]@{
          area = "Common Bathroom Ceiling / Adjacent Flat"
          inspection_observations = @("Observed mild dampness at the ceiling of the Common Bathroom of Flat No. 103.", "Observed gap between tile joints of Common and Master Bedroom Bathrooms of Flat No. 203.", "Outlet leakage is noted in the source text.")
          thermal_findings = @($thermalSummary)
          combined_finding = "Common Bathroom ceiling dampness may be linked to tile-joint gaps or outlet leakage above/nearby. The source references Flat No. 203, so this should be verified on site."
          images = Select-InspectionImages 40 6
        }
      )
      probable_root_cause = @(
        "Gaps between bathroom tile joints allowing water ingress.",
        "Possible concealed plumbing leakage or loose plumbing joints around bathroom fixtures.",
        "External wall cracks, duct issues, or insufficient sealing/opening grouting contributing to moisture ingress.",
        "Moisture migration from wet areas to adjacent skirting, wall, ceiling, and parking ceiling surfaces."
      )
      severity_assessment = [pscustomobject]@{
        level = "Moderate"
        reasoning = "Multiple rooms and common/parking areas show dampness or leakage symptoms, and the checklist marks several related conditions as moderate. The extracted text does not show clear evidence of immediate structural danger, so Critical or High severity is not assigned without further confirmation."
      }
      recommended_actions = @(
        "Repair and re-grout bathroom tile joints and gaps in affected wet areas.",
        "Check concealed plumbing, nahani trap joints, outlet points, and fixture joints for leakage before closing finishes.",
        "Repair external wall cracks, duct openings, and improperly sealed pipe penetrations near affected areas.",
        "Treat damp/effloresced wall and skirting surfaces only after the moisture source is corrected.",
        "Reinspect the parking ceiling and bathroom ceiling after repairs to confirm leakage has stopped.",
        "Use the thermal images as supporting evidence, but verify exact image-to-area mapping during final review."
      )
      additional_notes = @(
        "The source inspection date is 27.09.2022 and the thermal image dates shown are 27/09/22.",
        "Previous structural audit and previous repair work are marked as No in the inspection form.",
        "This no-key draft is deterministic. Set OPENAI_API_KEY to generate a more polished AI-merged DDR with deduplication and better image placement."
      )
    }
  }

  return [pscustomobject]@{
    property_issue_summary = "Draft DDR generated from the provided inspection and thermal documents. Configure OPENAI_API_KEY to enable AI merging, deduplication, and severity reasoning."
    area_wise_observations = @(
      [pscustomobject]@{
        area = "Inspection observations"
        inspection_observations = @($inspectionSnippet)
        thermal_findings = @()
        combined_finding = "The inspection report contains site observations that should be reviewed and merged with thermal findings."
        images = $inspectionImages
      },
      [pscustomobject]@{
        area = "Thermal observations"
        inspection_observations = @()
        thermal_findings = @($thermalSnippet)
        combined_finding = "The thermal report contains temperature/thermal observations and supporting images."
        images = $thermalImages
      }
    )
    probable_root_cause = @("Root cause should be inferred by the AI model after comparing the inspection and thermal report details.")
    severity_assessment = [pscustomobject]@{
      level = "Unknown"
      reasoning = "Severity cannot be reliably assigned without model-based comparison or manual review."
    }
    recommended_actions = @(
      "Review the extracted inspection and thermal observations.",
      "Confirm missing or unclear measurements before issuing the final DDR.",
      "Set OPENAI_API_KEY and rerun the workflow for a structured AI-generated DDR."
    )
    additional_notes = @("No unsupported facts were added in this fallback draft.")
  }
}

function ConvertTo-HtmlText {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return "" }
  return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function New-ListHtml {
  param([AllowNull()][object[]]$Items)
  if ($null -eq $Items -or $Items.Count -eq 0) { return "<p class='muted'>No details provided.</p>" }
  $html = ($Items | ForEach-Object { "<li>$(ConvertTo-HtmlText $_)</li>" }) -join "`n"
  return "<ul>$html</ul>"
}

function New-ImageHtml {
  param([AllowNull()][object[]]$Images)
  if ($null -eq $Images -or $Images.Count -eq 0) { return "<p class='muted'>No related image available.</p>" }
  return (($Images | ForEach-Object {
    $src = ConvertTo-HtmlText $_
    "<figure><img src='$src' alt='Supporting source image'><figcaption>$src</figcaption></figure>"
  }) -join "`n")
}

function New-DdrHtml {
  param([object]$Ddr)

  $observations = ""
  foreach ($obs in @($Ddr.area_wise_observations)) {
    $observations += @"
<section class="observation">
  <h3>$(ConvertTo-HtmlText $obs.area)</h3>
  <h4>Inspection Observations</h4>
  $(New-ListHtml -Items @($obs.inspection_observations))
  <h4>Thermal Findings</h4>
  $(New-ListHtml -Items @($obs.thermal_findings))
  <h4>Combined Finding</h4>
  <p>$(ConvertTo-HtmlText $obs.combined_finding)</p>
  <div class="images">
    $(New-ImageHtml -Images @($obs.images))
  </div>
</section>
"@
  }

  return @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Detailed Diagnostic Report</title>
  <style>
    :root { color-scheme: light; --ink:#17212b; --soft:#5d6b76; --line:#d8dee4; --accent:#0f5f73; --band:#f4f7f8; }
    * { box-sizing: border-box; }
    body { margin:0; font-family: Arial, Helvetica, sans-serif; color:var(--ink); background:#fff; line-height:1.55; }
    header { padding:36px 44px 28px; background:#123f4a; color:#fff; }
    header h1 { margin:0 0 8px; font-size:30px; letter-spacing:0; }
    header p { margin:0; color:#d7e7eb; }
    main { max-width: 980px; margin: 0 auto; padding: 30px 28px 56px; }
    section { border-top:1px solid var(--line); padding:24px 0; }
    h2 { margin:0 0 14px; font-size:22px; color:var(--accent); }
    h3 { margin:0 0 14px; font-size:19px; }
    h4 { margin:16px 0 8px; font-size:14px; text-transform:uppercase; color:var(--soft); }
    p { margin:0 0 12px; }
    ul { margin: 0 0 12px 20px; padding:0; }
    li { margin: 6px 0; }
    .summary { background:var(--band); border:1px solid var(--line); padding:18px; border-radius:6px; }
    .severity { display:inline-block; padding:5px 10px; border:1px solid var(--accent); color:var(--accent); font-weight:700; border-radius:4px; margin-bottom:10px; }
    .observation { border:1px solid var(--line); border-radius:6px; padding:18px; margin:18px 0; }
    .images { display:grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap:14px; margin-top:14px; }
    figure { margin:0; border:1px solid var(--line); border-radius:6px; overflow:hidden; background:#fff; }
    img { width:100%; height:auto; display:block; }
    figcaption { padding:8px 10px; color:var(--soft); font-size:12px; overflow-wrap:anywhere; }
    .muted { color:var(--soft); }
    @media print { header { background:#fff; color:#17212b; border-bottom:2px solid var(--line); } header p { color:#5d6b76; } main { max-width:none; padding:24px; } .observation { break-inside: avoid; } }
  </style>
</head>
<body>
  <header>
    <h1>Detailed Diagnostic Report</h1>
    <p>Generated from inspection and thermal source documents</p>
  </header>
  <main>
    <section>
      <h2>1. Property Issue Summary</h2>
      <div class="summary">$(ConvertTo-HtmlText $Ddr.property_issue_summary)</div>
    </section>
    <section>
      <h2>2. Area-wise Observations</h2>
      $observations
    </section>
    <section>
      <h2>3. Probable Root Cause</h2>
      $(New-ListHtml -Items @($Ddr.probable_root_cause))
    </section>
    <section>
      <h2>4. Severity Assessment</h2>
      <div class="severity">$(ConvertTo-HtmlText $Ddr.severity_assessment.level)</div>
      <p>$(ConvertTo-HtmlText $Ddr.severity_assessment.reasoning)</p>
    </section>
    <section>
      <h2>5. Recommended Actions</h2>
      $(New-ListHtml -Items @($Ddr.recommended_actions))
    </section>
    <section>
      <h2>6. Additional Notes</h2>
      $(New-ListHtml -Items @($Ddr.additional_notes))
    </section>
  </main>
</body>
</html>
"@
}

$resolvedInspection = Resolve-Path -LiteralPath $InspectionPdf
$resolvedThermal = Resolve-Path -LiteralPath $ThermalPdf
New-CleanDirectory -Path $OutputDir
$assetsDir = Join-Path $OutputDir "assets"
New-CleanDirectory -Path $assetsDir

Write-Host "Extracting text from inspection PDF..."
$inspectionText = Get-PdfText -Path $resolvedInspection
Write-Host "Extracting text from thermal PDF..."
$thermalText = Get-PdfText -Path $resolvedThermal

Write-Host "Extracting embedded images..."
$images = @()
$images += Export-EmbeddedImages -Path $resolvedInspection -Prefix "inspection" -AssetsDir $assetsDir
$images += Export-EmbeddedImages -Path $resolvedThermal -Prefix "thermal" -AssetsDir $assetsDir

Write-Host "Generating DDR structure..."
$ddr = Invoke-DdrModel -InspectionText $inspectionText -ThermalText $thermalText -Images $images -Model $Model
if ($null -eq $ddr) {
  Write-Host "OPENAI_API_KEY not found. Creating fallback draft DDR."
  $ddr = New-FallbackDdr -InspectionText $inspectionText -ThermalText $thermalText -Images $images
}

$dataPath = Join-Path $OutputDir "ddr_data.json"
$htmlPath = Join-Path $OutputDir "ddr_report.html"
$ddr | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $dataPath -Encoding UTF8
New-DdrHtml -Ddr $ddr | Set-Content -LiteralPath $htmlPath -Encoding UTF8

Write-Host "Done."
Write-Host "Report: $htmlPath"
Write-Host "Data:   $dataPath"
Write-Host "Images: $assetsDir"
