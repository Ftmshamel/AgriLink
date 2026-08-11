# AgriLink documentation

## What to submit for Week 5

**`Perono_ShamelFatima_Week5_APIIntegration.pdf`**

Four pages. Pages 1–2 are the documentation itself (API name, endpoints, sample
JSON response, explanation of the integration, error handling, and the
reflection), which keeps the body inside the 1–2 page limit. Pages 3–4 are
appendices holding the screenshots, the bonus features, and the testing notes,
since screenshots are a separate deliverable and should not count against the
page limit.

Each numbered section is marked `page-break-inside: avoid`, so a section is
moved whole to the next page rather than being cut in half.

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
