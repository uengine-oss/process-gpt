
export default class TenantAware {
    constructor(client) {
        this.client = client;
    }

    getTenantId() {
        const urlStr = window.location;
        const url = new URL(urlStr);

        let tenantId = url.hostname;
        if(tenantId.includes(".")){
            tenantId = tenantId.substring(tenantId.indexOf(".")+1)
        }

        return tenantId;
    }

    getProtocol() {
        return window.location.protocol;
    }
    
    getBucketByTenantId() {
        const urlStr = window.location;
        const url = new URL(urlStr);
        let bucket = null;

        let tenantId = url.hostname;
        if(tenantId.includes(".")){
            tenantId = tenantId.substring(tenantId.indexOf(".")+1);
        }

        bucket = tenantId.split('.')[0];

        return bucket;
    }
}