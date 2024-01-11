<script setup>
import DefaultLayoutWithVerticalNav from './components/DefaultLayoutWithVerticalNav.vue'
</script>

<template>
    <div>
        <DefaultLayoutWithVerticalNav>
            <RouterView />
        </DefaultLayoutWithVerticalNav>
    </div>
</template>

<style lang="scss">
@use "@layouts/styles/default-layout";
</style>
