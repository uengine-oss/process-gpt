<template>
    <div>
        <!-- <v-snackbar
                v-model="snackbar.status"
                :timeout="snackbar.timeout"
                :color="snackbar.color"
        >
            <v-btn @click="snackbar.status = false" variant="text">
                Close
            </v-btn>
        </v-snackbar> -->

        <div class="mb-2">
            <v-btn @click="openDialog"
                    color="primary"
                    class="mr-1"
                    prepend-icon="mdi-plus"
            >
                등록
            </v-btn>

            <v-btn @click="openDialog" 
                    color="primary"
                    class="mr-1"
                    prepend-icon="mdi-pencil"
            >
                수정
            </v-btn>
            
            <v-btn @click="updateTodolistDialog = true" 
                    color="primary"
                    prepend-icon="mdi-minus-circle-outline"
            >
                Todolist 업데이트
            </v-btn>
        </div>
        
        <div>
            <v-table hover>
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>액티비티 ID</th>
                        <th>액티비티명</th>
                        <th>시작일</th>
                        <th>완료일</th>
                        <th>마감일</th>
                        <th>프로세스 정의 ID</th>
                        <th>프로세스 인스턴스 ID</th>
                        <th>사용자 ID</th>
                    </tr>
                </thead>
                <tbody>
                    <tr v-for="(val, idx) in value" 
                            :key="val"
                            @click="goInstance(val.processInstanceId)"
                    >
                        <td class="font-semibold">{{ idx + 1 }}</td>
                        <td class="whitespace-nowrap" label="액티비티 Id">{{ val.activityId }}</td>
                        <td class="whitespace-nowrap" label="액티비티 이름">{{ val.activityName }}</td>
                        <td class="whitespace-nowrap" label="시작일">{{ val.startDate }}</td>
                        <td class="whitespace-nowrap" label="완료일">{{ val.endDate }}</td>
                        <td class="whitespace-nowrap" label="마감일">{{ val.dueDate }}</td>
                        <td class="whitespace-nowrap" label="프로세스 정의Id">{{ val.processDefinitionId }}</td>
                        <td class="whitespace-nowrap" label="프로세스 인스턴스Id">{{ val.processInstanceId }}</td>
                        <td class="whitespace-nowrap" label="사용자 Id">{{ val.userId }}</td>
                    </tr>
                </tbody>
            </v-table>
        </div>

        <v-dialog v-model="dialog"
                transition="dialog-bottom-transition"
                width="500"
        >
            <Todolist v-if="!selectedRow"
                    :editMode="true"
                    :inList="false"
                    v-model="newValue"
                    @closeDialog="closeDialog"
            />
            <Todolist v-else
                    :editMode="true"
                    :inList="false"
                    :isNew="false"
                    v-model="selectedVal"
                    @closeDialog="closeDialog"
            />
        </v-dialog>

        <v-dialog v-model="updateTodolistDialog" 
                transition="dialog-bottom-transition"
                width="500"
        >
            <UpdateTodolist
                    @closeDialog="updateTodolistDialog = false"
                    @updateTodolist="updateTodolist"
            ></UpdateTodolist>
        </v-dialog>
    </div>
</template>

<script>
import BaseGrid from '../base-ui/BaseGrid.vue'
import Todolist from '../Todolist.vue'
import UpdateTodolist from '../UpdateTodolist.vue'

export default {
    name: 'todolistGrid',
    mixins:[BaseGrid],
    components:{
        Todolist,
        UpdateTodolist,
    },
    data: () => ({
        path: 'todolist',
        updateTodolistDialog: false,
    }),
    created() {
        this.init(this.path);
    },
    methods: {
        goInstance(id) {
            this.$router.push(`/instances/${id}`);
        }
    }
}
</script>