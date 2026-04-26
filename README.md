# DDR Report Generation Workflow

This project builds a client-ready Detailed Diagnostic Report (DDR) from:

- an inspection/sample report PDF
- a thermal images/report PDF

It extracts text and images from both documents, merges the findings with an LLM when an API key is available, and generates a structured HTML DDR that can be opened in a browser or printed to PDF.

## Requirements

No Python or Node setup is required. The workflow runs with Windows PowerShell.

Optional:

- `OPENAI_API_KEY` environment variable for AI-generated merging and reasoning
- Poppler / `pdftotext` for best PDF text extraction. The script also checks the Git for Windows `pdftotext.exe` path when it is available.

## Run

```powershell
$env:OPENAI_API_KEY="your_api_key_here"
powershell -ExecutionPolicy Bypass -File .\scripts\Generate-Ddr.ps1 `
  -InspectionPdf .\data\sample_report.pdf `
  -ThermalPdf .\data\thermal_images.pdf `
  -OutputDir .\output
```

If `OPENAI_API_KEY` is not set, the script still extracts content and produces a draft DDR, but the AI reasoning/merging quality will be limited.

## Output

The script creates:

- `output\ddr_report.html` - final report
- `output\ddr_data.json` - structured data used to render the report
- `output\assets\...` - extracted source images

## DDR Sections

The generated report follows the assignment structure:

1. Property Issue Summary
2. Area-wise Observations
3. Probable Root Cause
4. Severity Assessment with reasoning
5. Recommended Actions
6. Additional Notes

Relevant extracted images are placed under the related observation sections where possible.
