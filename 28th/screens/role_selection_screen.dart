// ============================================================
// role_selection_screen.dart
// This is the screen a user lands on after the splash screen IF
// Firebase detects nobody is logged in on this device yet (see
// the navigation logic at the end of splash_screen.dart).
//
// It lets the user pick whether they're a tourist or a guide,
// which will determine which flow (quick setup vs. login/signup)
// they go through next.
// ============================================================

import 'package:flutter/material.dart';
import 'guide_login_screen.dart';
import 'tourist_setup_screen.dart';

// StatelessWidget is enough here because nothing on this screen changes
// over time on its own — there's no animation, no timer, no data that
// updates itself. It just displays fixed content and reacts to taps
// (which trigger navigation elsewhere, not a change to THIS screen).
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // SafeArea automatically adds padding so our content doesn't get
      // covered by the phone's notch, status bar, or home indicator —
      // important since this screen has content near the very top and
      // very bottom of the screen.
      body: SafeArea(
        // LayoutBuilder gives us access to how much actual space is
        // available to draw in (constraints.maxWidth / maxHeight).
        // We need this so we can check "does everything actually fit
        // this specific phone's screen?" further down.
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),

              // ---- WHY FittedBox HERE ----
              // We deliberately do NOT want this screen to scroll (the
              // person building this app wants everything visible at once,
              // even on small phones). The risk with that is: on a short
              // screen, content could overflow past the bottom edge and
              // get visually cut off/cause a rendering error.
              //
              // FittedBox(fit: BoxFit.scaleDown) solves this by shrinking
              // its ENTIRE child as one single unit, proportionally, but
              // ONLY if it doesn't already fit. On a normal/tall phone,
              // nothing shrinks at all — this only kicks in on small screens.
              // This keeps all the spacing/sizing ratios looking correct,
              // instead of each element shrinking independently and
              // looking disproportionate.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,

                // ConstrainedBox here forces our content to be exactly as
                // wide as the screen (not wider, not narrower) BEFORE
                // FittedBox considers scaling it down. Without this, the
                // Column below would size itself based on its widest child
                // instead of matching the actual screen width, which can
                // cause weird horizontal centering issues.
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    maxWidth: constraints.maxWidth,
                  ),
                  child: Column(
                    // mainAxisSize.min = only take up as much vertical space
                    // as the content actually needs, rather than stretching
                    // to fill the full screen height. This matters because
                    // FittedBox needs to know the Column's "natural" size
                    // in order to decide whether/how much to shrink it.
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---------------- TOP ROW: Logo + language pill ----------------
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TourTrack',
                            style: TextStyle(
                              fontFamily:'Nunito',
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F4E9E), // TourTrack brand blue
                            ),
                          ),
                          // The little yellow "English" pill in the top right.
                          // Currently just a static visual — not yet wired up
                          // to actually change the app's language.
                          // TODO: hook this up to real language-switching logic.
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFFDE59,
                              ), // TourTrack brand yellow
                              borderRadius: BorderRadius.circular(
                                30,
                              ), // fully rounded pill shape
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize
                                  .min, // pill hugs its content instead of stretching
                              children: [
                                Text(
                                  'English',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                SizedBox(
                                  width: 6,
                                ), // small gap between text and icon
                                Icon(Icons.language, size: 18),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28), // fixed gap below the top row
                      // ---------------- HEADING ----------------
                      const Text(
                        'Hello there!',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pick your role and lets get touring!',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ---------------- ROLE CARDS ----------------
                      // Both cards use the SAME _RoleCard widget (defined
                      // below), just with different icon/title/description/
                      // onTap values passed in. This avoids writing the same
                      // card layout twice — if we ever want to change how
                      // ALL cards look (padding, colors, etc.), we only have
                      // to edit it in ONE place.
                      _RoleCard(
                        icon: Icons
                            .luggage_rounded, // placeholder icon; swap for real suitcase illustration later
                        title: "I'm a tourist",
                        description:
                            'Here for the tour? Just a quick setup and we can begin',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TouristSetupScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16), // gap between the two cards
                      _RoleCard(
                        icon: Icons
                            .flag_rounded, // placeholder icon; swap for real flag illustration later
                        title: "I'm a guide",
                        description:
                            'Create or login to your account to begin a tour',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const GuideLoginScreen(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // ---------------- BIRD MASCOT ----------------
                      Center(
                        child: Image.asset(
                          'assets/images/bird_logo.png',
                          width: 160,
                          // errorBuilder shows a fallback icon if the image
                          // fails to load (e.g. wrong file name, not yet
                          // added to assets/images/) instead of crashing
                          // the whole screen. Once the real image is
                          // confirmed working, this fallback simply never
                          // triggers — safe to leave in permanently.
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.travel_explore,
                              size: 140,
                              color: Color(0xFFFFDE59),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ---------------- INFO BANNER ----------------
                      // The light-blue box explaining why TourTrack needs
                      // location access. Just informational — not interactive.
                      Container(
                        width:
                            double.infinity, // stretches to fill the full width
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFDCEFFB,
                          ), // light blue background
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          // Aligns the icon to the TOP of the text block
                          // (not vertically centered), so it lines up with
                          // the first line of text even if the text wraps
                          // onto multiple lines.
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.map_outlined,
                              color: Color(0xFF1F4E9E),
                            ),
                            const SizedBox(width: 12),
                            // Expanded forces the text to take up all
                            // remaining horizontal space in the Row (instead
                            // of overflowing off-screen), and lets it wrap
                            // onto multiple lines naturally.
                            Expanded(
                              child: Text(
                                'TourTrack shares your live location with '
                                'your guide so nobody gets left behind on a tour.',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F4E9E),
                                  height:
                                      1.4, // line spacing multiplier, improves readability for wrapped text
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// _RoleCard — a small, reusable widget representing ONE tappable
// role option (used twice above: once for "tourist", once for "guide").
//
// The underscore at the start of the name (_RoleCard) means this class
// is PRIVATE to this file — other files/screens can't import and use it
// directly. That's intentional here since it's only ever meant to be an
// internal building block for THIS screen, not a general-purpose widget
// used elsewhere in the app.
// ============================================================
class _RoleCard extends StatelessWidget {
  // These are the pieces of data that change between the two cards.
  // Instead of writing two nearly-identical blocks of UI code, we write
  // the layout ONCE and just plug in different values each time we use it.
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap; // a function to run when this card is tapped

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // InkWell wraps the card to make the ENTIRE thing tappable (not just
    // an icon or button inside it), and gives a standard Material "ripple"
    // animation on tap for free, so it visually feels tappable.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        20,
      ), // matches the Container's corners so the ripple effect stays within the rounded shape
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFDE59), // TourTrack brand yellow
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: Colors.black87),
            const SizedBox(width: 16),
            // Expanded here is important: without it, the title/description
            // Column would try to size itself based on its content, which
            // could push the chevron icon off-screen or cause overflow if
            // the description text is long. Expanded forces this middle
            // section to take up exactly the remaining space between the
            // icon and the chevron.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 15, color: Colors.grey[800]),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 26,
            ), // visual hint that tapping the card navigates forward
          ],
        ),
      ),
    );
  }
}
