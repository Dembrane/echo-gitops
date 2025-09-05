Run a simple chunked upload flow with k6.

Prereqs:
- Install k6: https://k6.io/docs/getting-started/installation/

Files:
- `userRecording.js`: Recorded flow from the browser (reference).
- `sendChunks.js`: Script that initiates a conversation, uploads `.webm` chunks, then finishes.
- `audioChunks/`: Place your chunk files named `chunk_000.webm`, `chunk_001.webm`, ...

Usage (recommended run from the `scripts/k6` directory):
```bash
cd scripts/k6
k6 run sendChunks.js \
  -e PROJECT_ID=YOUR_PROJECT_ID \
  -e START=0 -e END=3 \
  -e SLEEP=30 \
  -e CALL_FINISH=true
```

From project root:
```bash
(cd scripts/k6 && k6 run sendChunks.js \
  -e PROJECT_ID=YOUR_PROJECT_ID \
  -e START=0 -e END=25 \
  -e SLEEP=30 \
  -e CALL_FINISH=true)
```

Environment variables:
- `PROJECT_ID` (required): Target project id.
- `START`, `END` (optional): Inclusive indices for `chunk_XXX.webm` files. Defaults: `START=0`, `END=3`.
- `SLEEP` (optional): Seconds to wait between uploads. Default: `30`.
- `CHUNKS_DIR` (optional): Directory of chunks, default `audioChunks` (relative to `scripts/k6`).
- `CALL_FINISH` (optional): Whether to call `/finish` after last chunk, default `true`.

Behavior:
- Each run creates exactly one conversation and uploads files `chunk_START..chunk_END`.
- Each upload uses multipart fields: `chunk` (binary), `timestamp` (ISO), `source=PORTAL_AUDIO`, `run_finish_hook` (`true` on last chunk, else `false`).
- If `CALL_FINISH=true`, a final `/finish` call is made.

Notes:
- Do not set `content-type` manually for multipart; k6 sets the boundary automatically.
- Ensure your chunk files are present and named `chunk_XXX.webm` with zero padding (e.g., `chunk_000.webm`).

