<template>
    <div id="tree" ref="tree" class="org-chart"></div>
</template>

<script>
import OrgChart from '@balkangraph/orgchart.js'

export default {
    name: 'tree',
    props: {
        nodes: {
            type: Array,
            default: [],
        }
    },
    data: () => ({
    }),
    mounted() {
        this.mytree(this.$refs.tree, this.nodes);
    },
    methods: {
        mytree(domEl, x) {
            this.chart = new OrgChart(domEl, {
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
}
</script>

<style scoped>
.org-chart {
    height: calc(100vh - 112px);
}
</style>