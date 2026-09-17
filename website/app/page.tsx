const REPO = "https://github.com/rav4nn/calllane";

export default function Page() {
  return (
    <>
      <header className="top">
        <a className="brand" href="/">
          <PhoneIcon />
          CallLane
        </a>
        <a href={REPO}>GitHub</a>
      </header>

      <main>
        <section className="hero">
          <div className="hero-copy">
            <h1>Your music shouldn&rsquo;t go quiet just because you joined a call.</h1>
            <p className="lede">
              CallLane is a free, open-source menu-bar app for macOS. It stops the
              system from muting everything else during calls, and it keeps your
              AirPods at full quality by using your Mac&rsquo;s mic instead.
            </p>
            <div className="actions">
              <a className="button primary" href="#install">Install with Homebrew</a>
              <a className="button" href={REPO}>Source on GitHub</a>
            </div>
            <p className="fine">macOS 14 or later. No account. No kernel extension.</p>
          </div>
          <Demo />
        </section>

        <section className="fixes" id="how">
          <h2>Two fixes in one menu-bar icon</h2>
          <div className="fix">
            <h3>Media stays loud.</h3>
            <p>
              The moment a call starts, macOS drops every other sound by about 20 dB.
              No setting turns it off. CallLane gives your call app its own audio
              device, so the ducking applies to the call and nothing else. Music,
              videos and games stay at full volume.
            </p>
          </div>
          <div className="fix">
            <h3>Your headphones stay at full quality.</h3>
            <p>
              On a call, your Mac switches to your headphones&rsquo; microphone.
              Bluetooth can&rsquo;t carry high-quality audio and a mic at once, so
              everything collapses to tinny headset quality. CallLane pins the input
              to your Mac&rsquo;s built-in mic, which sounds better anyway, so your
              AirPods keep streaming at full quality.
            </p>
          </div>
        </section>

        <section className="setup" id="install">
          <div className="setup-copy">
            <h2>Setup takes about a minute</h2>
            <ol>
              <li>
                <strong>Install with Homebrew.</strong> Three commands, one admin
                password prompt.
                <pre><code>{`brew trust --tap rav4nn/tap
brew install --cask rav4nn/tap/calllane
xattr -dr com.apple.quarantine /Applications/CallLane.app`}</code></pre>
                <span className="note">
                  The last line is needed because CallLane is signed ad-hoc, not with
                  an Apple Developer ID. Without it macOS says it cannot verify the
                  app, and you must allow it once under Privacy &amp; Security.
                </span>
              </li>
              <li>
                <strong>In each call app, pick &ldquo;CallLane&rdquo; as the speaker.</strong>{" "}
                Once per app, before the call starts. Works with FaceTime, WhatsApp,
                Zoom, Meet, Slack, Teams and Discord. The setup guide in the menu
                shows the exact path for each one.
              </li>
              <li>
                <strong>Keep your headphones as the system output and turn on Lock input.</strong>{" "}
                That&rsquo;s it. The phone icon fills while a call is using CallLane.
              </li>
            </ol>
          </div>
          <figure className="panel">
            <picture>
              <source media="(prefers-color-scheme: dark)" srcSet="/panel-dark.png" />
              <img
                src="/panel-light.png"
                alt="The CallLane menu-bar panel: output picker, input picker with Lock input on, volume slider, and a status row reading CallLane in use"
                width={340}
                height={340}
              />
            </picture>
            <figcaption>The menu-bar panel. Output, input, lock, done.</figcaption>
          </figure>
        </section>

        <section className="limits" id="limits">
          <h2>Honest limits</h2>
          <ul>
            <li>Calls in Safari can&rsquo;t use CallLane. Safari has no per-site speaker picker.</li>
            <li>It adds about 10 to 15 ms of latency to call audio.</li>
            <li>Pick CallLane before the call starts. Once a call begins on your headphones, they hold the headset profile until you hang up.</li>
            <li>Spatial Audio and head tracking may not apply to the call.</li>
            <li>Requires macOS 14 or later. Tested on macOS 26 with AirPods Pro 3.</li>
            <li>Signed ad-hoc, so macOS asks you to allow it once. The install steps above cover it.</li>
          </ul>
        </section>

        <section className="privacy">
          <h2>Privacy</h2>
          <p>
            No account, no analytics, no network calls. CallLane reads its own hidden
            audio tap. It never touches your real microphone. The source is on GitHub:
            the app is MIT, the driver is GPL-3 and derived from BlackHole.
          </p>
        </section>
      </main>

      <footer>
        <span>CallLane</span>
        <a href={REPO}>Source</a>
        <a href={`${REPO}/releases`}>Releases</a>
        <a href={`${REPO}/issues`}>Report a problem</a>
        <a href="https://hardeep.cv">Made by Hardeep</a>
      </footer>
    </>
  );
}

function Demo() {
  return (
    <div className="demo" aria-label="Animated comparison: on a normal Mac the music level drops when a call starts; with CallLane it stays at full volume and the AirPods keep the listening profile.">
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
        <span className="db">−20 dB</span>
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
      <path
        fill="currentColor"
        d="M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1A17 17 0 0 1 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.3 0 .7-.2 1z"
      />
    </svg>
  );
}
