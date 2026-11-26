// Dotwell project page: latest release info, screenshot switcher and copy button.
// No dependencies. Everything degrades to static links if JavaScript or the GitHub API is unavailable.
(() => {
  const REPO = "Saissaken/dotwell";
  const CACHE_KEY = "dotwell.latestRelease";
  const CACHE_TTL = 10 * 60 * 1000; // The GitHub API allows 60 unauthenticated requests per hour.

  // Latest release

  const readCache = () => {
    try {
      const cached = JSON.parse(sessionStorage.getItem(CACHE_KEY));
      if (cached && Date.now() - cached.savedAt < CACHE_TTL) return cached.release;
    } catch {}
    return null;
  };

  const writeCache = (release) => {
    try {
      sessionStorage.setItem(CACHE_KEY, JSON.stringify({ savedAt: Date.now(), release }));
    } catch {}
  };

  const fetchLatestRelease = async () => {
    const cached = readCache();
    if (cached) return cached;
    const response = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!response.ok) throw new Error(`GitHub API: ${response.status}`);
    const data = await response.json();
    const dmg = (data.assets || []).find((asset) => asset.name.endsWith(".dmg"));
    const release = {
      version: String(data.tag_name || "").replace(/^v/, ""),
      url: data.html_url,
      publishedAt: data.published_at,
      dmgURL: dmg ? dmg.browser_download_url : null,
      dmgSize: dmg ? dmg.size : null,
    };
    writeCache(release);
    return release;
  };

  const formatDate = (iso) =>
    new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });

  const formatSize = (bytes) => `${(bytes / 1_000_000).toFixed(1)} MB`;

  const showRelease = (release) => {
    if (!release.version) return;
    const pill = document.querySelector("[data-release-pill]");
    if (pill) {
      pill.href = release.url;
      pill.querySelector("[data-release-pill-text]").textContent =
        `Version ${release.version} is out · ${formatDate(release.publishedAt)}`;
      pill.hidden = false;
    }
    const meta = document.querySelector("[data-version-meta]");
    if (meta) {
      const size = release.dmgSize ? `, ${formatSize(release.dmgSize)}` : "";
      meta.textContent = `Version ${release.version}${size} · `;
    }
    if (release.dmgURL) {
      document.querySelectorAll("[data-download]").forEach((link) => (link.href = release.dmgURL));
    }
  };

  fetchLatestRelease().then(showRelease).catch(() => {});

  // Screenshot switcher

  const captions = {
    healthy: "When everything is fine, the dot is green and the popover stays calm.",
    issues: "When something needs attention, the dot turns yellow or red and the problems move to the top.",
  };
  const tabs = document.querySelectorAll("[data-shot]");
  const dot = document.querySelector("[data-status-dot]");
  const caption = document.querySelector("[data-caption]");

  tabs.forEach((tab) =>
    tab.addEventListener("click", () => {
      const shot = tab.dataset.shot;
      tabs.forEach((other) => other.setAttribute("aria-selected", String(other === tab)));
      document.querySelectorAll("[data-shot-picture]").forEach((picture) => {
        picture.hidden = picture.dataset.shotPicture !== shot;
      });
      if (dot) dot.classList.toggle("warning", shot === "issues");
      if (caption) caption.textContent = captions[shot];
    }),
  );

  // Copy button

  document.querySelectorAll("[data-copy]").forEach((button) =>
    button.addEventListener("click", async () => {
      const code = button.parentElement.querySelector("code").textContent.trim();
      const label = button.querySelector("[data-copy-label]");
      try {
        await navigator.clipboard.writeText(code);
        label.textContent = "Copied";
        button.classList.add("copied");
      } catch {
        label.textContent = "Press ⌘C";
        const range = document.createRange();
        range.selectNodeContents(button.parentElement.querySelector("code"));
        const selection = getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
      }
      setTimeout(() => {
        label.textContent = "Copy";
        button.classList.remove("copied");
      }, 1800);
    }),
  );
})();
