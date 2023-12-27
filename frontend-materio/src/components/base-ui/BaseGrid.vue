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
        selectedRow: -1,
    }),
    created() {
        this.storage = new CommonStorageBase(this);
    }, 
    methods:{
        async init(path) {
            this.userInfo = await this.storage.getUserInfo();
            const jsonData = await this.storage.getObject(`db://${path}/${this.userInfo.name}`);
            if (jsonData) {
                this.value = Object.values(jsonData);
            }
        },
        addNewRow() {
            this.newValue = null;
            this.openDialog = true;
        },
        remove(value){
            var where = -1;
            for(var i=0; i<this.value.length; i++){
                if(this.value[i]._links.self.href == value._links.self.href){
                    where = i;
                    break;
                }
            }
            if(where > -1){
                this.value.splice(i, 1);
                this.$emit('input', this.value);
            }
        },
        selectedRow(val) {
            this.selectedVal = val;
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