"use strict";
(() => {
  const RELEASES = "https://github.com/opera7133/Utatane/releases";
  const API = "https://api.github.com/repos/opera7133/Utatane/releases?per_page=100";
  const LANGUAGES = ["ja", "en", "zh-Hans", "zh-Hant", "ko"];
  const language = LANGUAGES.includes(document.documentElement.lang) ? document.documentElement.lang : "ja";
  let releaseState = { kind: "loading" };
  const words = {
    ja: { loading:"最新リリースを確認中…", fallback:"取得できませんでした。GitHub Releasesからダウンロードできます。", all:"リリース一覧", page:"配布ページを開く", download:"macOS版をダウンロード", prerelease:" / 開発版", stable:" / 通常リリース", published:"公開", noAsset:"このリリースの配布ファイルを確認してください。" },
    en: { loading:"Checking the latest release…", fallback:"Couldn’t load the latest release. Downloads are available on GitHub Releases.", all:"All releases", page:"View downloads", download:"Download for macOS", prerelease:" / Pre-release", stable:" / Regular release", published:"Published", noAsset:"Check this release for available downloads." }
  };
  const localizedWords = {
  "ja": {
    "title": "Utatane — macOSで伺かを",
    "pause": "動きを止める",
    "resume": "動かす"
  },
  "en": {
    "title": "Utatane — Ukagaka for macOS",
    "pause": "Pause animation",
    "resume": "Play animation"
  },
  "zh-Hans": {
    "title": "Utatane — 在 macOS 上使用伺か",
    "pause": "暂停动画",
    "resume": "播放动画",
    "loading": "正在获取最新版本…",
    "fallback": "无法获取最新版本。可前往 GitHub Releases 下载。",
    "all": "版本列表",
    "page": "前往下载页面",
    "download": "下载 macOS 版",
    "prerelease": " / 开发版",
    "stable": " / 常规发布",
    "published": "发布于",
    "noAsset": "请在此版本页面查看可下载的文件。"
  },
  "zh-Hant": {
    "title": "Utatane — 在 macOS 上使用伺か",
    "pause": "暫停動畫",
    "resume": "播放動畫",
    "loading": "正在取得最新版本…",
    "fallback": "無法取得最新版本。可前往 GitHub Releases 下載。",
    "all": "版本列表",
    "page": "前往下載頁面",
    "download": "下載 macOS 版",
    "prerelease": " / 開發版",
    "stable": " / 一般發行版",
    "published": "發布於",
    "noAsset": "請在此版本頁面查看可下載的檔案。"
  },
  "ko": {
    "title": "Utatane — macOS에서 우카가카를",
    "pause": "애니메이션 일시 정지",
    "resume": "애니메이션 재생",
    "loading": "최신 릴리스 확인 중…",
    "fallback": "최신 버전을 불러오지 못했어요. GitHub Releases에서 다운로드할 수 있어요.",
    "all": "릴리스 목록",
    "page": "다운로드 페이지 열기",
    "download": "macOS 버전 다운로드",
    "prerelease": " / 개발 버전",
    "stable": " / 일반 릴리스",
    "published": "출시일",
    "noAsset": "이 릴리스의 다운로드 파일을 확인해 주세요."
  }
};
  for (const code of LANGUAGES) words[code] = { ...words[code], ...localizedWords[code] };
  const motionToggle = document.getElementById("motion-toggle");
  const title = document.getElementById("title");
  let paused = false;
  function renderMotion() {
    motionToggle.textContent = paused ? words[language].resume : words[language].pause;
    motionToggle.setAttribute("aria-pressed", String(paused));
  }
  motionToggle.hidden = false;
  title.classList.add("is-animated");
  motionToggle.addEventListener("click", () => {
    paused = !paused;
    title.classList.toggle("is-paused", paused);
    renderMotion();
  });
  const status = document.getElementById("release-status");
  const releaseLink = document.getElementById("release-link");
  const downloadLink = document.getElementById("download-link");
  const downloadLabel = document.getElementById("download-label");
  const releaseKind = document.getElementById("release-kind");

  function safeGitHubURL(value, pathPrefix) {
    try {
      const url = new URL(value);
      return url.origin === "https://github.com" && !url.username && !url.password &&
        url.pathname.startsWith(pathPrefix) ? url.href : null;
    } catch { return null; }
  }

  function renderRelease() {
    const w = words[language];
    releaseLink.href = RELEASES;
    releaseLink.textContent = w.all;
    downloadLink.href = RELEASES;
    downloadLabel.textContent = w.page;
    releaseKind.textContent = "";
    downloadLink.removeAttribute("download");
    if (releaseState.kind !== "ready") {
      status.textContent = releaseState.kind === "loading" ? w.loading : w.fallback;
      return;
    }
    const r = releaseState.release;
    releaseLink.href = r.url;
    releaseLink.textContent = r.name;
    releaseKind.textContent = r.prerelease ? w.prerelease : w.stable;
    downloadLink.href = r.assetURL || r.url;
    downloadLabel.textContent = r.assetURL ? w.download : w.page;
    const bits = [];
    if (r.date) bits.push(w.published + " " + new Intl.DateTimeFormat(language, { year:"numeric", month:"short", day:"numeric", timeZone:"Asia/Tokyo" }).format(r.date));
    if (r.size) bits.push(new Intl.NumberFormat(language, { maximumFractionDigits:1 }).format(r.size / 1048576) + " MB");
    if (!r.assetURL) bits.push(w.noAsset);
    status.textContent = bits.join(" · ");
  }

  async function fetchLatestVersion() {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    try {
      const response = await fetch(API, { signal:controller.signal, headers:{ Accept:"application/vnd.github+json" } });
      if (!response.ok) throw new Error("Release request failed");
      const data = await response.json();
      if (!Array.isArray(data)) throw new Error("Invalid release list");
      const releases = data.filter(r => r && !r.draft && typeof r.tag_name === "string" &&
        safeGitHubURL(r.html_url, "/opera7133/Utatane/releases/tag/"));
      releases.sort((a,b) => (Date.parse(b.published_at) || 0) - (Date.parse(a.published_at) || 0));
      const latest = releases[0];
      if (!latest) throw new Error("No published releases");
      const assets = Array.isArray(latest.assets) ? latest.assets : [];
      const asset = assets.find(a => a && a.name === "Utatane-macOS.zip" &&
        safeGitHubURL(a.browser_download_url, "/opera7133/Utatane/releases/download/"));
      const date = new Date(latest.published_at || NaN);
      releaseState = { kind:"ready", release:{
        name:latest.tag_name, url:safeGitHubURL(latest.html_url, "/opera7133/Utatane/releases/tag/"),
        prerelease:latest.prerelease === true, date:Number.isNaN(date.getTime()) ? null : date,
        assetURL:asset ? safeGitHubURL(asset.browser_download_url, "/opera7133/Utatane/releases/download/") : null,
        size:asset && Number.isFinite(asset.size) && asset.size > 0 ? asset.size : null
      }};
    } catch { releaseState = { kind:"error" }; }
    finally { clearTimeout(timeout); }
    renderRelease();
  }

  renderRelease();
  renderMotion();
  fetchLatestVersion();
})();
