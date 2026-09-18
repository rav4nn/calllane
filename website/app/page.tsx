const REPO = "https://github.com/rav4nn/calllane";

export default function Page() {
  return (
    <>
      <div className="nav-outer">
        <nav className="nav">
          <a className="nav-brand" href="/">
            <PhoneIcon />
            CallLane
          </a>
          <div className="nav-links">
            <a href="#how" className="nav-hide">How it works</a>
            <a href="#install" className="nav-hide">Install</a>
            <a href={REPO} className="btn btn-outline" target="_blank" rel="noopener noreferrer">GitHub</a>
          </div>
        </nav>
      </div>

      <main>
        <section className="hero wrap">
          <h1>Your music shouldn&rsquo;t go quiet when you join a call.</h1>
          <p className="hero-sub">
            A free, open-source menu-bar app for macOS. It stops the system from
            muting everything else during calls, and keeps your AirPods at full
            quality by using your Mac&rsquo;s mic instead.
          </p>
          <div className="hero-actions">
            <a className="btn btn-accent" href="#install">Install with Homebrew</a>
            <a className="btn btn-dark" href={REPO}>Source on GitHub</a>
          </div>
          <p className="hero-fine">macOS 14 or later &middot; No account &middot; No kernel extension</p>
          <Demo />
        </section>

        <section className="video-section wrap">
          <div className="video-frame">
            <video controls preload="metadata" playsInline poster="/demo-poster.webp">
              <source src="/demo-web.mp4" type="video/mp4" />
            </video>
          </div>
        </section>

        <section className="section wrap">
          <h2>Made for watching something together on a call</h2>
          <p className="section-muted">
            You are on FaceTime or WhatsApp with someone, and you press play on
            the same film. The second the call connects, the film drops to a
            whisper and the call sits on top of it. You turn the volume up, the
            call gets loud, the film is still quiet. CallLane ends that. The film
            plays at full volume, the call sits where you set it, and your AirPods
            sound like AirPods for the whole evening.
          </p>
        </section>

        <section className="section section-center wrap">
          <h2 className="voices-heading">You are not the only one</h2>
          <div className="voice-grid">
            <blockquote className="voice">
              <p>&ldquo;On full volume I can hardly hear anything.&rdquo;</p>
              <cite><a href="https://discussions.apple.com/thread/251775481" target="_blank" rel="noopener noreferrer"><AppleIcon /> Apple Community</a></cite>
            </blockquote>
            <blockquote className="voice">
              <p>&ldquo;Music from Spotify sounded like it was being transmitted over AM frequency.&rdquo;</p>
              <cite><a href="https://edwinb.co.uk" target="_blank" rel="noopener noreferrer"><GlobeIcon /> edwinb.co.uk</a></cite>
            </blockquote>
            <blockquote className="voice">
              <p>&ldquo;Audio ducking doesn&rsquo;t deactivate after the call. The only fix is restarting my Mac.&rdquo;</p>
              <cite><a href="https://discussions.apple.com/thread/253206466" target="_blank" rel="noopener noreferrer"><AppleIcon /> Apple Community</a></cite>
            </blockquote>
            <blockquote className="voice">
              <p>&ldquo;Your voice goes from studio-quality 48&thinsp;kHz to walkie-talkie 16&thinsp;kHz mono.&rdquo;</p>
              <cite><GitHubIcon /> GitHub</cite>
            </blockquote>
            <blockquote className="voice">
              <p>&ldquo;It has been a decade that people are facing this issue.&rdquo;</p>
              <cite><a href="https://discussions.apple.com/thread/252978122" target="_blank" rel="noopener noreferrer"><AppleIcon /> Apple Community</a></cite>
            </blockquote>
            <blockquote className="voice">
              <p>&ldquo;The &lsquo;fix&rsquo; of switching to the internal mic is not really a fix. It&rsquo;s a workaround.&rdquo;</p>
              <cite><a href="https://apple.stackexchange.com/questions/375995" target="_blank" rel="noopener noreferrer"><StackIcon /> StackExchange</a></cite>
            </blockquote>
          </div>
        </section>

        <section className="section wrap" id="how">
          <h2>Two fixes in one menu-bar icon</h2>
          <div className="feature-grid">
            <div className="feature-card">
              <h3>Media stays loud.</h3>
              <p>
                The moment a call starts, macOS drops every other sound by about
                20 dB. No setting turns it off. CallLane gives your call app its
                own audio device, so the ducking applies to the call and nothing
                else. Music, videos and games stay at full volume.
              </p>
            </div>
            <div className="feature-card">
              <h3>Your headphones stay at full quality.</h3>
              <p>
                On a call, your Mac switches to your headphones&rsquo; microphone.
                Bluetooth can&rsquo;t carry high-quality audio and a mic at once,
                so everything collapses to tinny headset quality. CallLane pins
                the input to your Mac&rsquo;s built-in mic, which sounds better
                anyway, so your AirPods keep streaming at full quality.
              </p>
            </div>
          </div>
          <div className="routing-wrap">
            <Routing />
          </div>
          <p className="works-note">Works with FaceTime, WhatsApp, Zoom, Meet, Slack, Teams and Discord.</p>
        </section>

        <section className="section wrap" id="install">
          <div className="setup-grid">
            <div>
              <h2>Setup takes about a minute</h2>
              <ol>
                <li>
                  <strong>Install with Homebrew.</strong> Three commands, one admin
                  password prompt.
                  <pre><code>{`brew trust --tap rav4nn/tap
brew install --cask rav4nn/tap/calllane
xattr -dr com.apple.quarantine /Applications/CallLane.app`}</code></pre>
                  <span className="note-text">
                    The last line is needed because CallLane is signed ad-hoc, not
                    with an Apple Developer ID. Without it macOS says it cannot
                    verify the app, and you must allow it once under
                    Privacy &amp; Security. This is not a normal requirement for
                    most Mac apps &mdash; notarization is planned.
                  </span>
                </li>
                <li>
                  <strong>In each call app, pick &ldquo;CallLane&rdquo; as the speaker.</strong>{" "}
                  Once per app, before the call starts.
                </li>
                <li>
                  <strong>Keep your headphones as the system output and turn on Lock input.</strong>{" "}
                  That&rsquo;s it. The phone icon fills while a call is using CallLane.
                </li>
              </ol>
            </div>
            <figure className="screenshot">
              <img
                src="/panel-light.png"
                alt="The CallLane menu-bar panel: output picker, input picker with Lock input on, volume slider, and a status row"
                width={340}
                height={340}
              />
              <figcaption>The menu-bar panel. Output, input, lock, done.</figcaption>
            </figure>
          </div>
        </section>

        <section className="section wrap beta-callout">
          <p className="beta-text">
            <strong>Early open-source beta.</strong> CallLane is currently ad-hoc
            signed, so macOS requires a one-time <code>xattr</code> step during
            installation. Notarization is planned. If you try it on a different
            Mac, headset, or call app,{" "}
            <a href={`${REPO}/issues`}>feedback is welcome</a>.
          </p>
        </section>

        <section className="section wrap" id="limits">
          <h2>Honest limits</h2>
          <ul className="limits-list">
            <li>It adds about 10 to 15 ms of latency to call audio. Imperceptible in use.</li>
            <li>Spatial Audio and head tracking may not apply to the call.</li>
            <li>Requires macOS 14 or later. Tested on macOS 26 with AirPods Pro 3.</li>
            <li>Open-source and ad-hoc signed. See the beta note above for details.</li>
          </ul>
        </section>

        <section className="section wrap">
          <h2>Privacy</h2>
          <p className="privacy-text">
            No account, no analytics, no network calls. CallLane reads its own
            hidden audio tap. It never touches your real microphone. The source is
            on GitHub: the app is MIT, the driver is GPL-3 and derived from
            BlackHole.
          </p>
        </section>
      </main>

      <footer className="footer wrap">
        <span>CallLane</span>
        <a href={REPO}>Source</a>
        <a href={`${REPO}/releases`}>Releases</a>
        <a href={`${REPO}/issues`}>Report a problem</a>
        <a href="https://hardeep.cv">Made by Hardeep</a>
      </footer>
    </>
  );
}

function Routing() {
  return (
    <svg className="routing" viewBox="0 0 720 220" role="img" aria-labelledby="routing-title">
      <title id="routing-title">Audio routing with CallLane. Spotify and Safari play straight to the headphones at full volume. FaceTime plays into the CallLane device, which is ducked 20 dB, then forwards to the headphones.</title>
      <defs>
        <marker id="arr" viewBox="0 0 6 6" refX="5" refY="3" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M0 0 L6 3 L0 6z" className="arrow-head" />
        </marker>
      </defs>
      <path className="wire wire-music" d="M185 40 C 380 40, 400 100, 530 100" markerEnd="url(#arr)" />
      <path className="wire wire-music" d="M185 100 L 530 100" markerEnd="url(#arr)" />
      <path className="wire wire-accent" d="M185 170 L 290 170" markerEnd="url(#arr)" />
      <path className="wire wire-accent" d="M445 170 C 490 170, 510 100, 530 100" markerEnd="url(#arr)" />
      <text className="wire-label" x="360" y="28">full volume</text>
      <text className="wire-label wire-label-accent" x="235" y="160">&minus;20 dB</text>
      <g className="rnode"><rect x="8" y="18" width="177" height="44" rx="22" /><text x="96" y="45">Spotify, YouTube</text></g>
      <g className="rnode"><rect x="8" y="78" width="177" height="44" rx="22" /><text x="96" y="105">Safari, games</text></g>
      <g className="rnode"><rect x="8" y="148" width="177" height="44" rx="22" /><text x="96" y="175">FaceTime, WhatsApp</text></g>
      <g className="rnode rnode-lane"><rect x="290" y="148" width="155" height="44" rx="22" /><text x="368" y="175">CallLane</text></g>
      <g className="rnode"><rect x="530" y="78" width="182" height="44" rx="22" /><text x="621" y="105">Your headphones</text></g>
    </svg>
  );
}

function Demo() {
  return (
    <div className="demo" aria-label="Animated comparison: on a normal Mac the music level drops when a call starts; with CallLane it stays at full volume.">
      <Panel title="A normal Mac" variant="ducked" />
      <Panel title="With CallLane" variant="lane" />
    </div>
  );
}

function Panel({ title, variant }: { title: string; variant: "ducked" | "lane" }) {
  return (
    <div className={`panel-card ${variant}`}>
      <div className="panel-head">
        <span>{title}</span>
        <span className="pill">Call joined</span>
      </div>
      <div className="row">
        <span className="label">Music</span>
        <span className="track"><span className="fill music" /></span>
        <span className="db">&minus;20 dB</span>
      </div>
      <div className="row">
        <span className="label">Call</span>
        <span className="track"><span className="fill call" /></span>
      </div>
      <div className="row profile">
        <span className="label">AirPods</span>
        <span className="swap">
          <span className="before">Listening, 48 kHz</span>
          <span className="after">{variant === "ducked" ? "Headset, 24 kHz" : "Listening, 48 kHz"}</span>
        </span>
      </div>
    </div>
  );
}

function PhoneIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="currentColor" d="M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1A17 17 0 0 1 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.3 0 .7-.2 1z" />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg className="cite-icon" width="24" height="24" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#555" d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
    </svg>
  );
}

function GitHubIcon() {
  return (
    <svg className="cite-icon" width="24" height="24" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#333" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0 1 12 6.844a9.59 9.59 0 0 1 2.504.337c1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.02 10.02 0 0 0 22 12.017C22 6.484 17.522 2 12 2z" />
    </svg>
  );
}

function GlobeIcon() {
  return (
    <svg className="cite-icon" width="24" height="24" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#e67e22" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z" />
    </svg>
  );
}

function StackIcon() {
  return (
    <svg className="cite-icon" width="24" height="24" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#f48024" d="M15 21H3v-8h2v6h10v-6h2v8zm-1.24-12.04l-1.43 1.39 6.22 6.4 1.43-1.39-6.22-6.4zm-2.58-2.87l-.75 1.75 7.63 3.27.75-1.75-7.63-3.27zm4.6 9.41H6.26v2h9.52v-2zm-9.52-2h9.52v2H6.26v-2z" />
    </svg>
  );
}
