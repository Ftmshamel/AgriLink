# AgriLink documentation

## What to submit for Week 5

**`Week5_API_Documentation.pdf`** — the 2-page deliverable. It covers the API
name, endpoints, a real sample JSON response, the explanation of the
integration, error handling, the bonus features, screenshots, and the
reflection.

## The other files

| File | What it is |
| --- | --- |
| `Week5_API_Documentation.html` | Source of the PDF. Edit this, then regenerate (below). |
| `API_INTEGRATION.md` | Long-form technical reference for the Open-Meteo weather integration. Not part of the submission — keep it as an appendix or for your own defence notes. |
| `screenshots/` | All eight screenshots, captured on a Pixel 9 emulator against the live APIs. |

## Regenerating the PDF

After editing the HTML, rebuild the PDF with Chrome — no extra software needed:

```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --headless --disable-gpu `
  --no-pdf-header-footer `
  --print-to-pdf="C:\Users\LAPTOP\AgriLink\docs\Week5_API_Documentation.pdf" `
  "file:///C:/Users/LAPTOP/AgriLink/docs/Week5_API_Documentation.html"
```

Or simply open the HTML in a browser and press Ctrl+P → *Save as PDF*, with
margins set to Default and "Background graphics" ticked so the tables keep their
shading.
