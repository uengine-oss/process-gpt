/* eslint-disable import/order */

import '@/@iconify/icons-bundle'
import App from '@/App.vue'
// import vuetify from '@/plugins/vuetify'
import { loadFonts } from '@/plugins/webfontloader'
import router from '@/router'
import '@/styles/styles.scss'
import '@core/scss/index.scss'
import { createPinia } from 'pinia'
import { createApp } from 'vue'
import axios from 'axios';
import { Icon } from '@iconify/vue';
import VCalendar from 'v-calendar';
import 'v-calendar/style.css'
import mitt from 'mitt';
// Vuetify
import 'vuetify/styles'
import { createVuetify } from 'vuetify'
import * as components from 'vuetify/components'
import * as directives from 'vuetify/directives'
const vuetify = createVuetify({
    components,
    directives,
  })

loadFonts()
const emitter = mitt();
const OpenGraphEmitter = mitt();
const ModelingEmitter = mitt();
// Create vue app
const app = createApp(App)
app.config.globalProperties.EventBus = emitter;
app.config.globalProperties.OGBus = OpenGraphEmitter;
app.config.globalProperties.ModelingBus = ModelingEmitter;
// Setting Config
axios.defaults.baseURL = '';
app.config.globalProperties.$axios = axios;

// Component
app.component('Icon',Icon)
// import OpenGraph from "./opengraph/Opengraph.vue"
// app.component('opengraph', OpenGraph)
// import BpmnRole from './components/designer/bpmnModeling/bpmn/role/Role.vue'
// app.component('bpmn-role', BpmnRole)
// import BpmnMessageFlow from './components/designer/bpmnModeling/bpmn/relation/MessageFlow.vue'
// app.component('bpmn-message-flow', BpmnMessageFlow)
// import BpmnRelation from './components/designer/bpmnModeling/bpmn/relation/Relation.vue'
// app.component('bpmn-relation', BpmnRelation)
// import BpmnInstanceVariables from './components/designer/bpmnModeling/bpmn/variable/BpmnInstanceVariables.vue'
// app.component('bpmn-instance-variables', BpmnInstanceVariables)
// import BpmnComponentChanger from './components/designer/bpmnModeling/bpmn/BpmnComponentChanger.vue'
// app.component('bpmn-component-changer', BpmnComponentChanger)
import ModelerImageGenerator from './components/designer/ModelerImageGenerator.vue'
app.component('modeler-image-generator', ModelerImageGenerator)
// modeler-image-generator
// Use plugins
import loadOpengraphComponents from './opengraph'
import loadbpmnComponents from './components/designer/bpmnModeling/bpmn'

loadOpengraphComponents(app)
loadbpmnComponents(app)

app.use(vuetify)
app.use(createPinia())
app.use(router)
app.use(VCalendar, {})

// Mount vue app
app.mount('#app')
