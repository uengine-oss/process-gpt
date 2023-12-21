<template>
    <div id="tree" ref="tree"></div>
</template>

<script>
import OrgChart from '@balkangraph/orgchart.js'

export default {
    name: 'tree',
    props: {
        nodes: {
            default: []
        }
    },
    data() {
    },
    methods: {
        mytree: function(domEl, x) {
            this.chart = new OrgChart (domEl, {
                template: 'rony',
                scaleInitial: 0.5,
                nodes: x,
                nodeBinding: {
                    field_0: "name",
                    img_0: "img"
                }
            });
        }
    },
    mounted(){
        this.mytree(this.$refs.tree, this.nodes)
    }
}
</script>