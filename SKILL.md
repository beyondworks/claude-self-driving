---
name: self-driving
description: "self-driving: a person only states the destination (the instruction), and a Claude Code session on the driver Mac finishes the work itself (opening apps, clicking, typing, recording, building, testing) through computer use, session messages, and shell commands. A person takes the wheel only at the stop points defined in this skill. Use for \"/self-driving\", \"self-driving\", \"record it yourself\", \"take over this dev task on the other Mac\", and Korean requests such as \"셀프 드라이빙\", \"셀프 드라이빙으로\", \"알아서 녹화해\", \"자율 개발 맡겨\"."
---

# self-driving (Self-driving Mac)

Meaning: the person only states the destination (the instruction). The driving (opening apps, clicking, typing, recording, building, testing) is done by a Claude Code session on the driver Mac. A person takes the wheel only when a "stop point" is hit. Reply to the person in the language they wrote in.

## Read the config first
At the start, read `config.json` in this skill folder (the install script creates it from `config.example.json`). Empty fields fall back to the defaults below. If a step needs a field with no default, stop at that step and tell the person which field to fill in.

| Field | Meaning | Default |
|---|---|---|
| `supervisor_session` | Session that sends instructions and checks results | This session |
| `dispatcher_session` | Session on the driver Mac that assigns work to worker sessions. If empty, the supervisor sends directly to worker sessions | Empty |
| `roles` | Worker session names by kind of work (e.g. `{"recording": "…", "dev": "…"}`) | Empty (the dispatcher decides) |
| `driver_ssh` | ssh target from the supervising Mac to the driver Mac (`user@host` or an ssh config alias). Empty when both are the same Mac | Empty |
| `result_dir` | Folder on the supervising Mac where results are collected | `~/self-driving-results` |
| `model` / `effort` | Model and effort level the worker session and any on-screen demo session must use | Empty (skip the check) |
| `away_file` | The Mac the person is using is driven only while this file exists (away marker) | Empty (never drive the person's Mac) |
| `lock_file` | Lock file so only one session holds the screen at a time | `~/.claude/self-driving.lock` |

## Who does what
- Supervisor session: forwards the person's instruction to the driving side, quoting it verbatim. Checks results directly in files, logs, and records before reporting to the person.
- Dispatcher session (if any): picks the worker session for the job (see `roles`).
- Worker session: carries the job to the end with computer use, session messages, and shell commands.

## 0. Who calls it
- Instructions come from the supervisor session only. Another session that needs self-driving asks the supervisor instead of sending to the driver Mac itself. Two sources of instructions on the same screen make recordings and controls collide.
- The default driver's seat is the driver Mac. The Mac the person is using right now is driven only under "Driving the person's Mac" below.

## Driving the person's Mac (only while they are away)
- Turn it on only when `away_file` is set and that file exists. Otherwise do not drive this Mac; send the job to the driver Mac.
- One session drives at a time. The supervisor picks the driving session and writes its name, start time, and task into `lock_file`. While that file exists, no other session touches the screen.
- Right before starting and at every step, check that `away_file` still exists. If it is gone (the person is back), stop immediately, then in order:
  1. Release screen control.
  2. Close only the windows you opened.
  3. Delete the lock file.
  4. Tell the supervisor how far you got.
- Do not touch windows, documents, or tabs the person left open. Work only in windows you opened, and when done close every window, recording, and server you started.
- If a new per-app computer-use grant (`request_access`) is needed, stop at that step and note it. The supervisor walks the person through all of them at once when they are back.
- When done, delete the lock file and send the supervisor what you did, when, the result files, and anything that blocked you.

## 1. Sending (supervisor session)
1. Find the receiving session: try `ListAgents` first. If it is on another Mac or another account and not listed, check that it runs with Remote Control and send to the address shown there. Waking a session can change its address, so look it up again every time.
2. Start the first line of the message with "self-driving: <one-sentence task>". The body includes:
   - The person's instruction, quoted verbatim (not summarized)
   - Acceptance criteria (scenes, features, done condition)
   - Model and effort level to use (if `model` / `effort` are set)
   - Where results go (`result_dir`)
   - The "Stop points" below
3. The other side may not report that it read the message. Track progress by reading the driver Mac's processes, files, and records directly (over ssh when `driver_ssh` is set).

## 2. Driving (worker session)
- Before starting
  - Make sure no other recording or screen control is running and that `lock_file` does not exist.
  - If `model` is set, confirm the worker session and any demo session that will appear on screen use that model (a new session opening with a different model has wasted real takes).
- Opening a new session: use the Claude app menu item that opens a new session in a new window. The "New" button inside a window may not respond.
- Recording
  - Record from the start in a clean new window.
  - Keep recorder or menu-bar app overlays out of the frame.
  - Cut any moment where an account email or a secret is visible.
  - When done, quit the recorder by pid and confirm no recording process is left.
- Autonomous development
  - Work on a feature branch (never commit straight to the default branch).
  - Finish tests and an on-screen check, then get an independent review.
  - Do not merge to the default branch or deploy to production. Report to the supervisor that it is ready and wait for the person to confirm.
- Never stop a process, server, or port you did not start in this run (another project's dev server may be on it). If a port is taken, pick a free one.
- When finished, put the result files in `result_dir` (scp if it is another Mac) and send the supervisor one report with file names, durations, the model check result, and anything that blocked you.

## Typing into the Claude app prompt box
- Computer-use tools do not accept the Claude app's own windows as a target. Do not keep requesting it. Opening a new session in the Claude app and typing into its prompt box is done with `tools/drive` in this skill folder. Keys and clicks go only to the Claude app process, never to whatever other app is in front.
- Setup (once)
  - Build with `swiftc -O tools/drive.swift -o tools/drive` (needs the Xcode command line tools).
  - The app that runs Claude Code needs macOS "Accessibility" permission. Without it, `drive` says so and stops. The person grants it in System Settings.
- Steps
  1. Open a new window with `tools/drive newwin "<File menu item that opens a new session in a new window>"`. The item name depends on the app's language, so look at the File menu once and copy it exactly (items outside the File menu are never clicked). It prints the new window number; every later command works only on that window.
  2. Capture just that window with `screencapture -x -o -l <window number> <file>` and find the prompt box. Screen coordinates = the window origin (points) from `tools/drive windows` + capture pixels divided by the display scale (2 on Retina).
  3. Click the prompt box with `tools/drive click <x> <y>`. Click the text area itself, at least 60pt in from both sides, so you never hit the "+" (attach) button on the left or the microphone on the right.
  4. Type with `tools/drive type "<instruction>"`, one character at a time. `type` and `enter` bring the Claude app to the front and refuse unless the window `newwin` opened is the frontmost window, so do this only on a driver Mac or while the person is away. If `type` stops partway, clear the prompt box before typing again. Each character is pasted (⌘V), so non-Latin text such as Korean is not garbled, and the previous clipboard is restored afterwards. Capture again to confirm the text went in as written.
  5. Send with `tools/drive enter`. Capture again a moment later to confirm the new session answered.
  6. Close only your own window with `tools/drive closewin`. Archive any sessions created for testing.
- What the tool blocks (enforced in code): clicks outside the prompt-box strip of the window `newwin` opened (matched by window number, not position), including the model and permission-mode row; keystrokes when that window is not frontmost; any action while the app shows a dialog or sheet; and **every click and keystroke after one send**. The prompt-box strip is a fixed offset that matches the current app layout; if an app update moves the model or permission-mode row, check the strip values in `drive.swift` again before using it. This tool only starts a new session with one instruction. Further conversation goes through session messages.
- Rules
  - Use it only for demos, recordings, and tests the person asked for. Capture first to confirm the target window, and never type into a window where another session is working.
  - Work handed between sessions goes through session messages (SendMessage), not this.
  - Never use it to click permission prompts, question buttons, or model and permission-mode settings. Never get around something an automatic safety check blocked by clicking or typing.
- Verified: open a new window → click the prompt box → type "Answer with today's date in one line" one character at a time → send → the new session answered with the date, with no human hands (macOS, Claude desktop app).

## Starting new sessions from a terminal (no desktop app)
- Use `tools/spawn start [--dir DIR] [--name NAME] [--mode MODE] [--visible] -- "<instruction>"` instead of `tools/drive`. It prints the new session id. Check it with `tools/spawn status <id>` and read the answer with `tools/spawn result <id>`.
- Same scope as drive: start one session with one instruction, nothing more. Do not use it to keep talking to a session; use session messages or let the person `claude --resume <id>`.
- Use `--visible` (macOS) only for demos a person asked for; headless is the default.
- Never start a session with wider permissions than your own (the tool cannot check this; it is your promise). The tool itself refuses `bypassPermissions` and `dontAsk` and defaults to `manual`; do not work around that.

## 3. Stop points (a person takes the wheel)
- When blocked, immediately send the supervisor the step, the time, and how to unblock it. The supervisor tells the person in a line or two which screen to open and what to press.
- A person always does or approves these:
  - Entering passwords, one-time codes, or recovery codes; OS permission dialogs (Screen Recording, Accessibility, etc.)
  - Payments and purchases
  - Sending mail or messages, public posts and uploads
  - Permanent data deletion
  - Reading, printing, or sending secrets (`.env` files, keys, tokens, passwords)
  - Accepting contracts or terms
  - Production deploys and merges to the default branch
- Never get around something an automatic safety check blocked by another route (such as clicking on screen).
- When the person says "stop", stop the recording process and the running turn right away and discard that take.
