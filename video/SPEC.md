# Cable Tester README film: spec

GOAL:    a visitor to the GitHub page sees, in 26 s, exactly what the app does: plug in a cable,
         read its watts and speed, save it, find it in History. Ends on the name and the repo link.
OUTPUT:  HyperFrames, 1920 x 1080, 30 fps. Silent (it loops inline in the README).
TIME:    26 s x 30 = 780 frames. splash 0-3 s, app 3-21 s, end card 21-26 s.

LOOK:    the app's own theme, Pure Black Lime, rebuilt from the SwiftUI views at 1.6x their point size.
         ground #000 (the brand is black; the window nearly fills the frame, 80 px margins, so there is
         no void), window #000 with a #1d1d1f 1 px border and 22 px radius, toolbar line #161616.
         ink #fff, secondary rgba(255,255,255,.55), tertiary .28. Accent lime #C5FA09, only on: the
         wattage, the Save button (ink #111014 text), the Thunderbolt bolt, checks, the plug's ledge.
         Tie dots keep their real cable colours. Face: SF Pro (the app's system font, SFNS.ttf), display
         700 at 180 px for the watts (112 pt x 1.6), titles 700 at 48 px, body 400-500 at 22-26 px.
OBJECTS: the real app icon (composited from App/AppIcon.icon layers); the app window with its traffic
         lights, sidebar toggle, title and clock button; the plug illustration (steel tip, lime ledge,
         dark housing) and the icon's bolt; the macOS arrow cursor at 58 px (5.4% of the height).

MOTION:  arrivals expo.out / power4.out; camera power2.inOut 0.5 s; exits power3.in, 40-50% shorter.
         Springs only on position/scale: checks back.out(2.2) (damping ~0.5, as in the app), plug
         back.out(1.6). Cascade = the app's: 45 ms stagger, 14 px rise, 0.5 s. Count-up 1.1 s power3.out.
         Cursor moves 0.55-0.7 s power2.inOut, click = 0.92 scale for 3 frames; the click causes the
         next thing on the same frame.

SHOTS:
  1  0.0-3.0   splash: icon lands 0.84 -> 1 with 10 px blur -> 0 (expo.out 0.8 s), "Cable Tester"
               letters 0.3 -> 1 opacity 0.05 s apart. 2.1-2.8 the icon's rounded square opens into
               the app window (clip-path, power3.inOut), black with its 1.5 px #1d1d1f border.
  2  3.0-5.3   the app fills in inside the window (toolbar, then body). Checklist: "Plug in a cable
               you want to test". No camera moves anywhere in the app (Max, 2026-11-22).
  3  4.6-7.3   Mac end in: plug rises, ledge lime, bolt outline draws, check 1 springs + tick draws,
               title swaps. Other end in (Mac): bolt fills and pops, check 2, "Reading the cable...".
  4  7.3-8.3   0.9 s hold, checklist cascades out, camera back to 1x.
  5  8.3-10.6  result cascades in; watts count 0 -> 240; "bolt USB 4 v2 . 80 Gb/s" (Thunderbolt 5);
               EPR, 5 A; inspector with the chip. Camera 1.3x on watts + data, then back.
  6  10.6-14.0 cursor enters, clicks Save; the save sheet drops with the values filled in; cursor
               picks the blue tie; clicks Save; sheet closes; button morphs to "Saved #13".
  7  14.0-15.0 cursor to the clock; click; the Now screen lifts away (0.22 s).
  8  15.0-20.4 History cascades in: 12 cables, #13 on top. Cursor clicks the Thunderbolt filter; the
               other rows fade, the 4 Thunderbolt rows slide up. Hold.
  9  20.4-21.0 the window shrinks into the icon (carry across, blur peak 8 px).
  10 21.0-26.0 end card: icon lands, "Cable Tester" wipes in beside it, one line, then the GitHub chip
               "github.com/Maxaubert/cable-tester". Held 2.5 s.

BANNED:  zoom-ins and punch-ins; history rows visible before their cascade; glow except the app's own bolt glow; floating particles; glass cards; a title over a dimmed
         screenshot; the logo docked in a corner; invented UI (every control is in the app); text
         moving while it is read; breathing loops other than the app's own pulsing ring.
QA:      0.8 splash; 3.2 settle; 5.6 check 1; 7.0 both checks; 9.4 count-up; 11.4 sheet; 13.6 saved;
         16.8 history full; 19.2 filtered; 20.7 carry; 23.0 + 25.5 end card.
