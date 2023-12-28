<template>
    <div ref="container" class="vue-bpmn-diagram-container"></div>
</template>
  
<script>
import BpmnJS from 'bpmn-js/dist/bpmn-navigated-viewer.production.min.js';
import BpmnModeler from 'bpmn-js/lib/Modeler';

export default {
    name: 'vue-bpmn',
    props: {
        url: {
            type: String,
        },
        bpmn: {
            type: String,
        },
        options: {
            type: Object
        }
    },
    data: function() {
        return {
            diagramXML: null
        };
    },
    mounted() {
        var container = this.$refs.container;

        var self = this;
        var _options = Object.assign({
            container: container,
            keyboard: {
                bindTo: window
            }
        }, this.options)
        this.bpmnViewer = new BpmnModeler(_options)//new BpmnJS(_options);  //

        this.bpmnViewer.on('import.done', function(event) {
            var error = event.error;
            var warnings = event.warnings;

            if (error) {
              self.$emit('error', error);
            } else {
              self.$emit('shown', warnings);
            }

            self.bpmnViewer.get('canvas').zoom('fit-viewport');
        });

        if (this.url) {
            this.fetchDiagram(this.url);
        } else if(this.bpmn) {
            this.diagramXML = this.bpmn
        }
    },
    beforeDestroy() {
        this.bpmnViewer.destroy();
    },
    watch: {
        url(val) {
            this.$emit('loading');
            this.fetchDiagram(val);
        },
        diagramXML(val) {
            this.bpmnViewer.importXML(val);
        }
    },
    methods: {
        fetchDiagram(url) {
            var self = this;

            fetch(url).then((response) => {
                return response.text();
            }).then((text) => {
                self.diagramXML = text;
            }).catch((err) => {
                self.$emit('error', err);
            });
        }
    }
};
  </script>
  
<style>
.vue-bpmn-diagram-container {
    height: 100%;
    width: 100%;
}
</style>
  