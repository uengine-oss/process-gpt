const modules = import.meta.glob("@/opengraph/**/*.vue", { eager: true });

export default function loadOpengraphComponents(app) {
    
  for (const path in modules) {
    const componentName = path.split("/").at(-1).split(".")[0];
    app.component(`${modules[path].default.name}`, modules[path].default);
  }
}