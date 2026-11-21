# Decisions

These are already decided. They carry over from the old Shilp repo. Change one only when I say so.

## The laptop
Dell Latitude 3180: Celeron N3350 (2 cores), 4 GB RAM, Intel HD 500, 128 GB M.2 SATA SSD (GPT),
Intel AC-7265 Wi-Fi. It runs Windows 10 for now, and a full backup image plus a rescue ISO are on an external drive.
I have one 64 GB pendrive. Golem runs from it until I decide to install to the SSD.

## Principles
- **Truthful:** it does only what I say, shows what it did, and does nothing in the background.
- **Default = deny:** apps get nothing unless their zone and settings allow it.
- **Keyboard first:** no taskbar, no Start menu, no bars, no desktop popups.
- **Light:** it has to run well on the laptop above.
- **Ask first:** no code gets written before the need is clear.

## Specific decisions
| Topic | Decision |
|---|---|
| Base | NixOS, built from this repo. GitHub checks every change and builds the installer. |
| Account | User name `shilpkaar`. It's never shown or typed at login. |
| Zones | RED: nothing, disposable, wiped on close. OFFLINE: no internet, own folder. YELLOW: internet, no files. GREEN: trusted. BLUE (my AI) comes later. |
| Permissions | Each app's settings decide (allowed or never). Nothing is asked at launch. An app with no settings asks for its zone once. |
| Network | Wi-Fi off at every start. No time sync over the internet. |
| Windows | Tiling with an existing engine. No gaps, titles or borders, only a 1 px line on the focused window. Focus moves by keys only. |
| Close | Closing a window asks for confirmation. This is the one allowed popup. |
| Notifications | None. Only a full-screen red alert, dismissed by pressing a key several times. |
| Lock | No username and no box: type the password and press Enter. Wrong tries are logged. |
| Lid | Closing it sleeps. On wake, Caps Lock ON means no lock, and OFF means lock. |
| Panels | The Control Panel and every system panel run in the GREEN zone. Apply asks the password once. |
| Look | A dark void with pale, cold light. Game-like, eventually a "shadow realm". |
| Terminal | A light terminal now, Cool Retro Term later. |
| BIOS password | No. A PC password, maybe later. |
| Windows OS | Gets wiped, but only at the very end, after Golem works fully from the pendrive. |
