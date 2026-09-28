# Module 10: a guard that ends a stuck TextInputHost before it cooks the laptop - Plain Language

> Session record generated 2026-09-28

---

## What happened

Your laptop felt hot underneath while its temperature read 48 C. The fan readings were right. The heat came from TextInputHost, a part of Windows 11 that draws the touch keyboard, the emoji panel and clipboard history. One small part of it had got stuck in a loop and kept one processor core busy at 99 %, doing nothing useful. Nothing on screen showed it.

Ending it fixed the heat at once: the processor went from 48.1 C to 41.1 C within two minutes, and Windows started a fresh copy by itself. But the fresh copy got stuck again. Testing showed what set it off on this laptop: a screenshot taken by the Claude Code screen-control tool, which hides that program's windows while it captures the screen. One screenshot, and within 15 to 30 seconds the loop was back.

Module 10 keeps this under control. It installs a guard that checks TextInputHost every 10 minutes and ends it only when it has used a whole processor core for a full minute. It needs no administrator rights, shows no window, and does not switch any Windows feature off.

## Honest state of play

Finished and working on this laptop. The guard is installed. The real scheduled task caught a stuck copy at 97.1 % of one core and ended it, with no window appearing. The safety self-test passes 62 of 62 checks. The undo is proven: install, undo and compare came back exactly as before, and the undo-to-original and undo-of-an-undo both worked.

Not done: nobody else has reviewed it yet (no adversarial audit). It has not been tried on another computer, another version of Windows, or with other screen-capture tools. Heavy real use of the panels, such as long voice typing, was not measured.

## Worst case if something is wrong

The worst realistic case is the guard ending TextInputHost while you are using one of its panels. Example: you dictate with voice typing for several minutes, TextInputHost happens to use 90 % of a core for a full minute while you do, and the voice-typing panel closes. You press the keys again and a fresh copy opens it. Nothing you already typed is lost. Nobody has measured whether normal use can reach 90 % for a minute; idle copies measured here used under 2 %.

## What changed for you

**A stuck TextInputHost**
- Before: It could hold a processor core for hours. On this laptop it used about four hours of processor time in one day.
- After:  The guard ends it at most about 11 minutes after it gets stuck: up to 10 minutes until the next check, plus the one-minute measurement.
- Affects: everyone who installs the guard

**Knowing what happened**
- Before: Nothing told you. The only sign was a warm laptop and a busier fan.
- After:  Each time the guard ends a stuck copy it writes one line in `guard-log.txt`, and option 1 shows it.
- Affects: everyone who installs the guard

**The touch keyboard, emoji panel and clipboard history**
- Before: Working.
- After:  Still working. The guard never switches them off; Windows starts a fresh copy the next time you open one.
- Affects: everyone

## What you can do now

- See in one click whether TextInputHost is using the processor right now, with option 1.
- Have a stuck TextInputHost ended automatically, every 10 minutes, with no window and no administrator password.
- End a stuck copy yourself, straight away, with option 9.
- Read in `guard-log.txt` exactly when the guard ended a stuck copy and how busy it was.
- Remove the guard at any time with option 6, or go back to before it was ever installed with option 7.
- Reach all of it from the control panel, under [T].

## What is still missing

- **A fix for the cause** - The guard ends a stuck copy after the fact. The loop itself is inside Windows, and on this laptop a screen-capture tool sets it off. Until Microsoft or the tool's maker fixes it, the guard keeps ending it.
- **An independent review (adversarial audit)** - Every other finished module in this project was reviewed by a second pair of eyes looking for mistakes. This one has only been tested by its builder.
- **Tests on other computers and Windows versions** - If you copy the module to another computer, check it with option 1 and option 2 before relying on it.

## How to check that what we say is done actually works

**Step 1:**
```bash
Double-click `1 - Check what is on now.cmd` in the module folder.
```
  - **Pass:** It shows TextInputHost using under 2 % of one core, and the guard as installed, running every 10 minutes, with a recent 'last ran' time.

**Step 2:**
```bash
Double-click `8 - Test the safety logic.cmd`.
```
  - **Pass:** It ends with 'checks passed : 62' and 'checks failed : 0'.

**Step 3:**
```bash
After a session in which a screen-control tool took screenshots, wait 15 minutes, then run option 1 again.
```
  - **Pass:** Either TextInputHost is idle, or the log shows a line such as 'ended TextInputHost pid 17384: 97.1 % of one core for 60 s'.

**Step 4:**
```bash
Run option 7, then option 5, then option 4.
```
  - **Pass:** Option 5 prints 'PASS - everything came back to exactly where it started', and option 4 ends with 'changed: 1'.


## Should you be concerned?

Not about the guard itself. It runs as you with your normal rights, it can only end a program called TextInputHost.exe from the Windows SystemApps folder in your own session, and it leaves everything else alone. Every change it makes is backed up first and can be undone with one click. The bigger point is the cause: on this laptop, a screenshot by the Claude Code screen-control tool is enough to start the loop. While any such tool controls your screen, expect TextInputHost to need ending, and let the guard do it.

## Glossary

**TextInputHost** - The part of Windows 11 that draws the touch keyboard, emoji panel, clipboard history and voice typing.

**Processor core** - One of the processor's independent workers; this laptop has 12 logical ones, and a stuck program can keep one busy all the time.

**Thread** - A single line of work inside a program; one stuck thread was enough to hold a whole core.

**Scheduled task** - An instruction to Windows to run a program at set times, here every 10 minutes.

**Round trip** - A test that installs, undoes and compares, to prove the undo really works.

## Claim Sources

| Claim | Basis | Evidence |
|-------|-------|----------|
| The heat came from TextInputHost | 📄 stated in input | processor 48.1 C and 20 % total load before; 41.1 C and 2 % two minutes after |
| A screenshot by the Claude Code tool set it off | 📄 stated in input | one screenshot at 18:42:10, and by 18:42:26 it was at 19.7 CPU-seconds |
| The guard works for real | 📄 stated in input | ended TextInputHost pid 17384 at 97.1 % of one core over 60 s and logged it; no window |
| The worst case is a panel closing mid-use | 🤖 model inference | *(none - model judgment)* |
| Screen-control tools will keep triggering it | 🤖 model inference | *(none - model judgment)* |
| Nothing typed is lost when it is ended | 🤖 model inference | *(none - model judgment)* |


---
**How to verify this document:**
`📄 stated in input` - the model's phrasing of something your source text said.
Find the matching line in the original to verify.
`🤖 model inference` - the model's own judgment or synthesis. Treat as opinion,
not measurement. Re-run on the same input and check whether specific numbers
stay consistent between runs.

*Session record. Plain-language track. Its developer twin covers the same session in technical detail.*