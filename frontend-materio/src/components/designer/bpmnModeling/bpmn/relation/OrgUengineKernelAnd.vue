
<script>
    import Or from './OrgUengineKernelOr.vue'

    export default {
        mixins: [Or],
        name: 'org-uengine-kernel-And',
        data: function() {
            return {
                myConditionType: 'And',
                conditionTypeAndOr: 'org.uengine.kernel.And'
            }
        }
    }

</script>
