<template>
    <div>
        <geometry-element
                selectable
                movable
                resizable
                connectable
                deletable
                :id.sync="value.tracingTag"
                :x.sync="value.elementView.x"
                :y.sync="value.elementView.y"
                :width.sync="value.elementView.width"
                :height.sync="value.elementView.height"
                :_style.sync="style"
                :parentId.sync="value.elementView.parent"
                :label.sync="namePanel"
                :customMoveActionExist="canvas.isCustomMoveExist"
                v-on:customMoveAction="delayedMove"
                v-on:moveShape="onMoveShape"
                v-on:dblclick="showProperty"
                v-on:selectShape="closeComponentChanger(); selectedActivity();"
                v-on:deSelectShape="closeComponentChanger(); deSelectedActivity();"
                v-on:removeShape="onRemoveShape"
                v-on:redrawShape="closeComponentChanger"
                v-on:addedToGroup="onAddedToGroup"
        >
            <geometry-polygon :vertices="[[0, 50],[50, 100],[100, 50],[50, 0]]"></geometry-polygon>
            <geometry-line :from="[20, 50]" :to="[80, 50]" :_style="{'stroke-width': 5}"></geometry-line>
            <geometry-line :from="[50, 20]" :to="[50, 80]" :_style="{'stroke-width': 5}"></geometry-line>

            <sub-elements>
                <bpmn-state-animation :status="status" :type="type"></bpmn-state-animation>
            </sub-elements>
            
            <sub-elements v-for="(index) in newEditUserImg.length" :key="index">
                <image-element
                        v-bind:image="newEditUserImg[index-1].picture"
                        :sub-width="'24px'"
                        :sub-height="'24px'"
                        :sub-right="(10*(index-1))+'px'"
                        :sub-bottom="value.elementView.height"
                ></image-element>
            </sub-elements>
            
            <bpmn-sub-controller :type="type"></bpmn-sub-controller>
        </geometry-element>

        <bpmn-gateway-panel
                v-if="drawer"
                v-model="value"
                @close="closePanel"
        ></bpmn-gateway-panel>
    </div>
</template>

<script>
    import IBpmn from '../IBpmn.vue'
    import BpmnPropertyPanel from './GatewayPanel.vue'

    export default {
        mixins: [IBpmn],
        name: 'bpmn-parallel-gateway',
        props: {},
        component: {
            'bpmn-gateway-panel': BpmnPropertyPanel
        },
        computed: {
            defaultStyle(){
                return {
                    'label-position': 'bottom',
                    'label-width': 120,
                }
            },
            type(){
                return 'Gateway'
            },
            className(){
                return 'org.uengine.kernel.bpmn.ParallelGateway'
            },
            createNew(newTracingTag, x, y, width, height, elementId){
                return {
                    _type: this.className(),
                    name: '',
                    tracingTag: newTracingTag,
                    elementView: {
                        '_type': 'org.uengine.kernel.view.DefaultActivityView',
                        'id': elementId,
                        'x': x,
                        'y': y,
                        'width': width,
                        'height': height,
                        'style': JSON.stringify({})
                    }
                }
            }
        },
        data: function () {
            return {};
        },
        watch: {},
        mounted: function () {
        },
        methods: {}
    }
</script>


<style scoped lang="scss" rel="stylesheet/scss">

</style>
