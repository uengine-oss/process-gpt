<template>
    <v-card>
        <v-toolbar color="primary"
                title="Todolist 등록"
                density="compact"
        >
            <v-btn @click="closeDialog"
                    icon="mdi-close"
                    color="default"
            ></v-btn>
        </v-toolbar>

        <v-card-text class="px-4 py-2">
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
            <v-btn color="primary"
                    variant="flat"
                    @click="save"
            >
                저장
            </v-btn>
        </v-card-actions>
    </v-card>
</template>


<script>
import BaseEntity from './base-ui/BaseEntity.vue'
import TextField from './primitives/TextField.vue'
import DateField from './primitives/DateField.vue'

export default {
    name: 'Todolist',
    mixins:[BaseEntity],
    components:{
        TextField,
        DateField,
    },
    data: () => ({
        path: "todolist"
    }),
    created(){
    },
    computed:{
    },
    methods: {
    },
}
</script>
