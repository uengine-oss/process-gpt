const modules = import.meta.glob("@/components/designer/bpmnModeling/bpmn/**/*.vue", { eager: true });

export default function loadBpmnComponents(app) {
  const bpmnComponents = {}
  for (const path in modules) {
    const componentName = path.split("/").at(-1).split(".")[0];
    app.component(`${modules[path].default.name}`, modules[path].default);
    bpmnComponents[componentName] = modules[path];
  }
  window.bpmnComponents = bpmnComponents
}