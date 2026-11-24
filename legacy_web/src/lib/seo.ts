export const seo = (title: string, description: string) => ({
  meta: [
    { title: `${title} · Biffy` },
    { name: "description", content: description },
    { property: "og:title", content: `${title} · Biffy` },
    { property: "og:description", content: description },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ],
});
