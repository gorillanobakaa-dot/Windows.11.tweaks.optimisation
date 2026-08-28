import json
import sys
import dual_track

def main():
    payload = {
        "injectSteps": [
            {
                "ephemeralMessage": (
                    "CRITICAL SYSTEM OVERRIDE: Dual-Track Documentation & GitHub Formatting Required.\n\n"
                    "=== DEVELOPER TRACK ===\n" + dual_track.CODE_DEV_SYSTEM + "\n\n"
                    "=== LAYMAN TRACK ===\n" + dual_track.CODE_LAYMAN_SYSTEM + "\n\n"
                    "=== GITHUB PUBLISHING STANDARD ===\n"
                    "1. SEAMLESS NAVIGATION: Every README or root document MUST contain direct hyperlinks to all related modules and sub-documents. Users must be able to click through the entire architecture without manually browsing the repo.\n"
                    "2. EMBEDDED MEDIA: Screenshots must be embedded directly on the page, at maximum width, and fully clickable. Use the format: [![Alt Text](path.png)](path.png). NEVER use 'click here to see gallery' links.\n"
                    "3. DUAL-TRACK ONLY: Never upload a module without ensuring both Layman (Track 1) and Developer (Track 2) documentation exist, following IBM style."
                )
            }
        ]
    }
    print(json.dumps(payload))
    sys.exit(0)

if __name__ == "__main__":
    main()
