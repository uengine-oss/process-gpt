<template>
  <div>
    <slot>
    </slot>
  </div>
</template>

<script>
  import OpengraphElement from './OpengraphElement.vue'
  export default {
    mixins: [OpengraphElement],
    name: 'horizontal-lane-element',
    props: {},
    computed: {},
    data: function () {
      return {}
    },
    watch: {},
    mounted: function () {

    },
    methods: {
      generateShape: function () {
        var me = this;
        return new OG.shape.HorizontalLaneShape(me.label);
      }
    }
  }
</script>


<style scoped lang="scss" rel="stylesheet/scss">

</style>

