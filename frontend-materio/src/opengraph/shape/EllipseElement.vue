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
    name: 'ellipse-element',
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
        return new OG.shape.EllipseShape(me.label);
      }
    }
  }
</script>


<style scoped lang="scss" rel="stylesheet/scss">

</style>

