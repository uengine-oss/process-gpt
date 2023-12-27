<template></template>

<script>
import CommonStorageBase from "@/components/storage/CommonStorageBase";

export default {
    name: 'BaseGrid',
    data: () => ({
        storage: null,
        dialog: false,
        value: null,
        userInfo: null,
    }),
    created() {
        this.storage = new CommonStorageBase(this);
    }, 
    methods:{
        async init(path) {
            this.userInfo = await this.storage.getUserInfo();
            const jsonData = await this.storage.getObject(`db://${path}/${this.userInfo.email}`);
            if (jsonData) {
                this.value = Object.values(jsonData);
            }
        },
        addNewRow() {
            this.newValue = null;
            this.openDialog = true;
        },
        openDialog(){
            this.dialog = true;
        },
        closeDialog(){
            this.dialog = false;
        }
    },
}
</script>