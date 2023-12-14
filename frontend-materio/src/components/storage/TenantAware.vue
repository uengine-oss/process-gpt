<template></template>

<script>
    export default {
        name: "TenantAware",
        components: {},
        props: {},
        methods: {
            getTenantId() {
                var urlStr = window.location;
                var url = new URL(urlStr);

                var tenantId = url.hostname;
                if(tenantId.includes(".")){
                    tenantId = tenantId.substring(tenantId.indexOf(".")+1)
                }

                return tenantId;
            },
            getProtocol() {
                return window.location.protocol;
            },
            getBucketByTenantId() {
                var urlStr = window.location;
                var url = new URL(urlStr);
                var bucket = null

                var tenantId = url.hostname;
                if(tenantId.includes(".")){
                    tenantId = tenantId.substring(tenantId.indexOf(".")+1)
                }
                bucket = tenantId.split('.')[0]
                return bucket;
            }
        }
    };
</script>
