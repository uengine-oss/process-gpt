<template>
    <v-card>
        <v-card-title>
            Update Todolist
        </v-card-title>

        <v-card-text class="pa-3">
            <TextField label="액티비티 Id" v-model="value.activityId" :editMode="editMode" />
            <TextField label="액티비티 이름" v-model="value.activityName" :editMode="editMode" />
            <DateField label="시작일" v-model="value.startDate" :editMode="editMode" />
            <DateField label="완료일" v-model="value.endDate" :editMode="editMode" />
            <DateField label="마감일" v-model="value.dueDate" :editMode="editMode" />
            <TextField label="프로세스 정의Id" v-model="value.processDefinitionId" :editMode="editMode" />
            <TextField label="프로세스 인스턴스Id" v-model="value.processInstanceId" :editMode="editMode" />
            <TextField label="사용자 Id" v-model="value.userId" :editMode="editMode" />
        </v-card-text>

        <v-card-actions class="justify-end">
            <v-btn color="deep-purple lighten-2"
                    variant="text"
                    @click="updateTodolist"
            >
                Update
            </v-btn>
            <v-btn color="deep-purple lighten-2"
                    variant="text"
                    @click="close"
            >
                Close
            </v-btn>
        </v-card-actions>
    </v-card>

</template>

<script>
import TextField from './primitives/TextField.vue'
import DateField from './primitives/DateField.vue'

export default {
    name: 'UpdateTodolistCommand',
    components:{
        TextField,
        DateField,
    },
    data: () => ({
        editMode: true,
        value: {},
    }),
    created() {
        this.value.activityId = '';
        this.value.activityName = '';
        this.value.startDate = '2023-12-12';
        this.value.endDate = '2023-12-12';
        this.value.dueDate = '2023-12-12';
        this.value.processDefinitionId = '';
        this.value.processInstanceId = '';
        this.value.userId = '';
    },
    methods: {
        updateTodolist() {
            this.$emit('updateTodolist', this.value);
        },
        close() {
            this.$emit('closeDialog');
        },
        change() {
            this.$emit("update:modelValue", this.value);
        },
    }
}
</script>

