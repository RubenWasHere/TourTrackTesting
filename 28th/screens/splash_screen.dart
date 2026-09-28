// ============================================================
// splash_screen.dart
// This is the FIRST screen shown when the app launches (set as
// `home:` in main.dart). Its two jobs are:
//   1. Play a short branded animation (bird pops in + pecks,
//      then the "TourTrack" wordmark fades in underneath).
//   2. While that's playing, quietly check Firebase to see if
//      this device already has someone logged in, then navigate
//      to the correct next screen once the animation finishes.
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'guide_home_screen.dart';
import 'role_selection_screen.dart';

// This screen uses StatefulWidget (not StatelessWidget) because it needs
// to run an ANIMATION over time, and animations require internal state
// that changes on every frame (~60x per second). A StatelessWidget can't
// hold onto that kind of ongoing, changing state.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

// `with TickerProviderStateMixin` — animations need something called a
// "ticker" that fires on every single frame to drive the motion smoothly.
// This mixin provides that ticker capability to our State class.
// We use the PLURAL "TickerProvider" (not "SingleTickerProvider") because
// we have TWO separate AnimationControllers below (bird + wordmark) — if
// we only had one animation total, "Single" would be enough.
class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // AnimationController is essentially a stopwatch that counts from 0.0 to
  // 1.0 over a set duration. Everything else (scale, rotation, opacity)
  // just "watches" this value and maps it to something visual.
  // We have TWO controllers because the bird and wordmark animate on
  // separate timelines (wordmark only starts AFTER the bird finishes).
  late AnimationController _birdController;
  late Animation<double> _scaleAnimation;    // drives the bird's pop-in size
  late Animation<double> _rotationAnimation; // drives the bird's "peck" tilt

  late AnimationController _wordmarkController;
  late Animation<double> _wordmarkFade; // drives the wordmark's fade-in opacity

  // initState() runs ONCE, right when this screen is first created.
  // This is the standard place to kick off animations, timers, or any
  // one-time setup — NOT inside build(), since build() can re-run many times.
  @override
  void initState() {
    super.initState();

    // ---------------- BIRD ANIMATION SETUP ----------------
    _birdController = AnimationController(
      vsync: this, // tells this controller which ticker to sync with (provided by the mixin above)
      duration: const Duration(milliseconds: 1600), // total time the bird's whole animation takes
    );

    // Scale: bird grows from invisible (0.0) to full size (1.0).
    // We only use the FIRST 60% of the controller's timeline for this
    // (Interval(0.0, 0.6)) — the remaining 40% is reserved for the peck.
    // Curves.easeOutBack makes it slightly OVERSHOOT past full size before
    // settling back — that's what creates the little "pop" bounce feel.
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _birdController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    // Rotation ("peck"): happens during the LAST 40% of the timeline
    // (Interval(0.6, 1.0)), i.e. only after the pop-in has finished.
    // TweenSequence lets us chain two motions together instead of one
    // straight line: first tilt DOWN (0.0 -> 0.15 radians ≈ 8.6°),
    // then tilt back UP (0.15 -> 0.0) — giving a quick peck-like nod.
    // `weight` controls how the two halves split the available time
    // (50/50 here, so the down-tilt and up-tilt take equally long).
    _rotationAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.15), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: 0.0), weight: 50),
    ]).animate(
      CurvedAnimation(
        parent: _birdController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeInOut),
      ),
    );

    // ---------------- WORDMARK ANIMATION SETUP ----------------
    // Separate, independent controller — this is what lets the wordmark
    // fade in on its OWN timing, starting only once the bird is fully done,
    // rather than being squeezed into the bird's existing timeline.
    _wordmarkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // just a simple fade, so a short duration
    );

    _wordmarkFade = CurvedAnimation(
      parent: _wordmarkController,
      curve: Curves.easeIn,
    );

    // Starts the bird animation playing immediately when this screen loads.
    _birdController.forward();

    // Listens for the bird animation's status. The moment it reaches
    // AnimationStatus.completed (i.e. hits 1.0 and finishes), we trigger
    // the wordmark's fade-in. This is what creates the "bird finishes,
    // THEN text appears" sequencing instead of everything animating at once.
    _birdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _wordmarkController.forward();
      }
    });

    // ---------------- NAVIGATION AFTER SPLASH ----------------
    // Future.delayed waits a set amount of REAL time, then runs the code
    // inside. 2500ms gives both animations (1600ms bird + 500ms wordmark
    // fade, which starts after the bird ends) enough time to fully finish
    // playing before we navigate away, plus a little breathing room so it
    // doesn't feel rushed.
    //
    // IMPORTANT: if you ever change the animation durations above, this
    // delay needs to stay >= (bird duration + wordmark duration), or the
    // screen will navigate away before the wordmark finishes appearing.
    Future.delayed(const Duration(milliseconds: 2500), () {
      // Safety check: if the user somehow already left this screen before
      // this timer finished (rare, but possible), `mounted` prevents us
      // from trying to navigate on a screen that no longer exists, which
      // would otherwise crash the app.
      if (!mounted) return;

      // This is the actual login check. FirebaseAuth automatically
      // persists login sessions on-device, so this reads instantly from
      // local storage — no network call needed, no loading delay.
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        // Nobody is logged in on this device yet -> this must be a first
        // launch (or they logged out) -> send them to pick a role.
        //
        // pushReplacement (instead of a plain push) REPLACES this splash
        // screen in the navigation history rather than stacking on top of
        // it. This matters because we don't want the user to be able to
        // hit the phone's back button and end up back on the splash screen.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
        );
      } else {
        // Already logged in on this device -> skip role selection entirely
        // and go straight to their home screen.
        // TODO: once real tourist/guide home screens exist, route to the
        // correct one based on their saved role instead of always MyHomePage.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const GuideHomeScreen()),
        );
      }
    });
  }

  // dispose() runs when this screen is being removed/destroyed.
  // AnimationControllers MUST be manually disposed here, or they'll keep
  // running in the background and leak memory — Flutter doesn't clean
  // these up automatically for you.
  @override
  void dispose() {
    _birdController.dispose();
    _wordmarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Grabs the device's screen width so we can size the bird/wordmark
    // relative to the actual screen instead of using a fixed pixel value —
    // this keeps them looking proportionally correct across different
    // phone sizes (small phones vs large phones/tablets).
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          // mainAxisSize.min = only take up as much vertical space as the
          // children actually need, rather than stretching to fill the
          // whole screen height. Keeps the bird+wordmark grouped together
          // and centered as one unit.
          mainAxisSize: MainAxisSize.min,
          children: [
            // AnimatedBuilder re-runs its `builder` function every single
            // frame that _birdController ticks, which is what makes the
            // scale/rotation values update smoothly in real time.
            AnimatedBuilder(
              animation: _birdController,
              builder: (context, child) {
                // Transform.scale and Transform.rotate are nested here —
                // scale wraps rotate, so the bird scales up AND rotates
                // around its own center simultaneously, using the current
                // frame's values from our two animations above.
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Transform.rotate(
                    angle: _rotationAnimation.value, // in radians, not degrees
                    child: child,
                  ),
                );
              },
              // The actual bird image being animated. Passed in as `child`
              // (rather than rebuilt inside `builder`) as a performance
              // optimization — Flutter reuses this exact widget every frame
              // instead of recreating the Image widget 60 times per second.
              child: Image.asset(
                'assets/images/bird_logo.png',
                width: screenWidth * 1, // currently full screen width
              ),
            ),
            const SizedBox(height: 16), // fixed gap between bird and wordmark
            // FadeTransition is a simpler, built-in shortcut for opacity
            // animations specifically — we don't need AnimatedBuilder here
            // since all we're animating is a single opacity value.
            FadeTransition(
              opacity: _wordmarkFade,
              child: Image.asset(
                'assets/images/tour_track_wordmark.png',
                width: screenWidth * 1, // currently full screen width
              ),
            ),
          ],
        ),
      ),
    );
  }
}