<template>
    <div class="my-3">
        <div v-if="editMode">
            <v-text-field 
                    v-model="value"
                    @change="change"
                    :label="label"
                    placeholder="입력하세요."
                    density="compact"
            ></v-text-field>
        </div>
        <div v-else>
            {{ label }} : {{ modelValue }} 
        </div>
    </div>
</template>

<script>
export default {
    props: {
        modelValue:{
            type: String,
            default: null /// TODO '' is not null !
        },
        editMode: Boolean,
        label: String,
    },
    data: () => ({
        value: null,
    }),
    created(){
        this.value = this.modelValue
    },
    methods:{
        change(){
            if(this.modelValue===null) this.value = null  //TODO '' is not null
            this.$emit("update:modelValue", this.value);
        }
    }
}
</script>
