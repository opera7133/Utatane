import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import navigation from "../Docs/navigation.json" with { type: "json" };
import { origin, base, repositoryURL } from "./src/site.mjs";

export default defineConfig({
  site: origin,
  base: base ? `/${base}` : "/",
  outDir: `./dist/${base ? `${base}/` : ""}`,
  trailingSlash: "ignore",
  integrations: [
    starlight({
      title: "Utatane Docs",
      defaultLocale: "root",
      locales: { root: { label: "日本語", lang: "ja" } },
      logo: { src: "./public/assets/utatane-icon.png" },
      favicon: "/assets/utatane-icon.png",
      social: [{ icon: "github", label: "GitHub", href: repositoryURL }],
      sidebar: [
        { label: "ドキュメントの入口", link: "/docs/" },
        ...navigation.groups.map((group) => ({
          label: group.label,
          items: group.pages.map((page) => ({
            label: page.title,
            link: `/docs/${page.slug}/`,
          })),
        })),
        { label: "公式紹介サイト", link: "/" },
      ],
      customCss: ["./src/styles/docs.css"],
      components: { ThemeSelect: "./src/components/ThemeSelect.astro" },
      editLink: { baseUrl: `${repositoryURL}/edit/main/` },
    }),
  ],
});
