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
                        <th>No</th>
                        <th>액티비티</th>
                        <th>프로세스 인스턴스</th>
                        <th>프로세스</th>
                        <th>시작일</th>
                        <th>완료일</th>
                        <th>마감일</th>
                        <th>담당자</th>
                        <th>상태</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>
                    <tr v-for="(val, idx) in value" 
                            :key="val"
                            @click="goInstance(val.instanceId)"
                            class="todolist-item"
                    >
                        <td>{{ idx + 1 }}</td>
                        <td>{{ val.activityId }}</td>
                        <td>{{ val.instanceId }}</td>
                        <td>{{ val.definitionId }}</td>
                        <td>{{ val.startDate }}</td>
                        <td>{{ val.endDate }}</td>
                        <td>{{ val.dueDate }}</td>
                        <td>{{ val.userId }}</td>
                        <td>{{ val.status }}</td>
                        <td>
                            <v-btn @click.stop="deleteWorkItem(val.key)"
                                    :disable="val.status === 'Completed'"
                                    icon="mdi-delete"
                                    variant="text"
                                    size="x-small"
                            ></v-btn>
                        </td>
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
        this.init();
    },
    methods: {
        goInstance(id) {
            this.$router.push(`/instances/${id}`);
        },
        async deleteWorkItem(id) {
            if (confirm("해당 Item 을 삭제 하시겠습니까?")) {
                const path = `db://${this.path}/${this.userInfo.email}`;
                if (id) {
                    await this.storage.delete(`${path}/${id}`);
                    await this.init();
                }
            }
        },

    }
}
</script>

<style scoped>
.todolist-item {
    cursor: pointer;
}
</style>