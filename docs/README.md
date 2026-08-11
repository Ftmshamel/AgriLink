# AgriLink documentation

## What to submit for Week 5

**`Perono_ShamelFatima_Week5_APIIntegration.pdf`**

Four pages: two pages of documentation (API name, endpoints, sample JSON
response, explanation of the integration, error handling, bonus features, and
the reflection), followed by a two-page screenshot appendix. The screenshots sit
in an appendix on purpose, so the documentation itself stays within the 1–2 page
limit while the screenshots remain a separate deliverable.

## The other files

| File | What it is |
| --- | --- |
| `Perono_ShamelFatima_Week5_APIIntegration.html` | Source of the PDF. Edit this, then regenerate (below). |
| `API_INTEGRATION.md` | Long-form technical reference for the Open-Meteo weather integration. Not part of the submission — keep it as an appendix or for defence notes. |
| `screenshots/` | Ten screenshots, captured on a Pixel 9 emulator against the live APIs. |

## Regenerating the PDF

After editing the HTML, rebuild the PDF with Chrome — no extra software needed:

```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --headless --disable-gpu `
  --no-pdf-header-footer `
  --print-to-pdf="C:\Users\LAPTOP\AgriLink\docs\Perono_ShamelFatima_Week5_APIIntegration.pdf" `
  "file:///C:/Users/LAPTOP/AgriLink/docs/Perono_ShamelFatima_Week5_APIIntegration.html"
```

Or open the HTML in a browser and press Ctrl+P → *Save as PDF*, with margins set
to Default and "Background graphics" ticked so the tables keep their shading.
