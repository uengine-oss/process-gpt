<template>
    <div>
        <vue-bpmn
                :bpmn="bpmn"
                :options="options"
                v-on:error="handleError"
                v-on:shown="handleShown"
                v-on:loading="handleLoading"
        ></vue-bpmn>
    </div>
</template>

<script>
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage";

import VueBpmn from './Bpmn.vue';

export default {
    name: "ProcessDefinition",
    components: {
        VueBpmn
    },
    props: {
        processDefinition: Object,
        bpmn: Object
    },
    data: () => ({
        options: {
            propertiesPanel: {},
            additionalModules: [],
            moddleExtensions: []
        }
    }),
    created() {
    },
    methods:{
        handleError() {
            console.error('failed to show diagram', err);
        },
        handleShown() {
            console.log('diagram shown');
        },
        handleLoading() {
            console.log('diagram loading');
        },
    },
}
</script>