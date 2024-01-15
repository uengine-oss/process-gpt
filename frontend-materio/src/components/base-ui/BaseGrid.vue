<template></template>

<script>
import CommonStorageBase from "@/components/storage/CommonStorageBase";

export default {
    name: 'BaseGrid',
    data: () => ({
        storage: null,
        dialog: false,
        value: null,
        userInfo: {},
    }),
    created() {
        this.storage = new CommonStorageBase(this);
    }, 
    methods:{
        async init() {
            if (this.path) {
                this.userInfo = await this.storage.getUserInfo();
                this.getData();
            }
        },
        async getData() {
            await this.storage.watch(`db://${this.path}/${this.userInfo.email}`, (callback) => {
                if (callback) {
                    this.value = Object.values(callback);
                }
            });
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
        },
    },
}
</script>