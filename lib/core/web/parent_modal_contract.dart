library;

/// The contract shared between this app and the marketing site's GTM tag.
///
/// Platform-independent on purpose: both the web implementation and the
/// non-web stub import it, so these values are safe to reference anywhere.

/// The exact payload the parent's GTM listener matches on. Changing this string
/// requires changing the GTM tag in lockstep.
const String kCloseRegistrationModal = 'close_registration_modal';

/// Origins permitted to embed this app.
///
/// Passed as `postMessage`'s `targetOrigin`, so the browser delivers the
/// message only if the real parent origin matches one of these — a message
/// aimed at the wrong origin is dropped by the browser, never leaked. Both the
/// apex and `www.` host are listed because either may serve the landing page.
const List<String> kTrustedParentOrigins = <String>[
  'https://mypocketpos.in',
  'https://www.mypocketpos.in',
];
