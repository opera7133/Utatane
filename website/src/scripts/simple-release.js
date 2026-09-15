(async function fetchLatestVersion() {
        const versionEl = document.getElementById("latest-version");
        const releaseLinkEl = document.getElementById("release-link");
        const releaseDateEl = document.getElementById("release-date");
        const downloadLinkEl = document.getElementById("download-link");
        const versionInfoEl = document.getElementById("version-info");

        try {
          const response = await fetch(
            "https://api.github.com/repos/opera7133/Utatane/releases",
          );
          if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
          }
          const releases = await response.json();
          const latestRelease =
            releases.find((release) => !release.draft) || releases[0];

          if (latestRelease) {
            const version = latestRelease.tag_name || latestRelease.name;
            if (versionEl) {
              versionEl.textContent = version;
            }
            if (releaseLinkEl && latestRelease.html_url) {
              releaseLinkEl.href = latestRelease.html_url;
            }
            const releaseDateStr =
              latestRelease.published_at || latestRelease.created_at;
            if (releaseDateEl && releaseDateStr) {
              const date = new Date(releaseDateStr);
              if (!isNaN(date.getTime())) {
                const year = date.getFullYear();
                const month = String(date.getMonth() + 1).padStart(2, "0");
                const day = String(date.getDate()).padStart(2, "0");
                const hours = String(date.getHours()).padStart(2, "0");
                const minutes = String(date.getMinutes()).padStart(2, "0");
                releaseDateEl.textContent = ` / ${year}-${month}-${day} ${hours}:${minutes} 更新`;
              }
            }
            const zipAsset = latestRelease.assets?.find(
              (asset) =>
                asset.name === "Utatane-macOS.zip" ||
                asset.name.endsWith(".zip"),
            );
            if (downloadLinkEl && zipAsset?.browser_download_url) {
              downloadLinkEl.href = zipAsset.browser_download_url;
              downloadLinkEl.setAttribute("download", zipAsset.name);
            } else if (downloadLinkEl && latestRelease.html_url) {
              downloadLinkEl.href = latestRelease.html_url;
            }
          }
        } catch (error) {
          console.warn("最新バージョンの取得に失敗しました:", error);
          if (versionInfoEl) {
            versionInfoEl.innerHTML =
              "（最新リリースの <code>Utatane-macOS.zip</code>）";
          }
        }
      })();
