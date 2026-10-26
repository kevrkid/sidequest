# Live Translate test kit

A fake phone camera filming a test street scene (brick wall, a menu board, a tilted street sign, a door sign) while
it holds still, then pans, zooms and tilts. Every frame carries its number (12 squares along the bottom), and gen.py
writes where every line of text is in every frame, so the tests can measure how far each translation box sits from
the words it covers.

    python gen.py                        # out/cam.mjpeg + cam.json (360 frames, ~70 MB; out/ is not committed)
    python gen.py 360 2.5 fast           # the same, moving 2.5× as fast
    python gen.py 360 1 para 1.4         # signs on a nearer layer than the wall (parallax)
    python track_unit.py ../lens.js      # the tracker alone, on known moves
    python track_live.py cam 40          # lens.js live for 40 s against a server on $SQ_BASE (default :8798)
    LENS_PROMPT_FILE=... python flow.py  # the whole flow from Scout's button (server running with a fake Claude that
                                         # writes each prompt to $LENS_PROMPT_FILE and answers "ES: <line>" per line)

Needs Playwright + Pillow. Start the server from a throwaway copy with empty data (see CLAUDE.md).
    LENS_PROMPT_FILE=... FAKE_LANG_FILE=... python photo.py   # Detect + 🖼 photos (a French sign, a 45-line menu, no camera);
                                         # the fake Claude answers the language question with what's in $FAKE_LANG_FILE
