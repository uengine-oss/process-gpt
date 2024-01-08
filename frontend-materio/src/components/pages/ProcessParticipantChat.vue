<template>
    <div>
        <chat :messages="messages"
                :disableChat="disableChat"
                @sendMessage="beforeSendMessage"
                @editSendMessage="editSendMessage"
        >
            <template v-slot:alert>
                <v-alert
                        icon="mdi-info"
                        :title="alertInfo.title"
                        :text="alertInfo.text"
                ></v-alert>
            </template>
            <!-- <template v-slot:tool="{message}">
                
            </template> -->
            
        </chat>
    </div>
</template>

<script>
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage";

import ChatGenerator from "../ai/ProcessInstanceGenerator.js";
import Chat from "../ui/Chat.vue";

import ChatModule from "../ChatModule.vue";


export default {
    mixins: [ChatModule],
    name: 'ProcessParticipantChat',
    components: {
        Chat,
    },
    data: () => ({
        definitions: [],
        processDefinition: null,
        processInstance: null,
        path: "instances",
        organizationChart: [],
        alertInfo: {
            title: "프로세스 실행",
            text: "대화형으로 프로세스를 실행하십시오. 예를 들어, '휴가를 신청할게: 1. 사유: 개인사유 2. 휴가 시작일: 오늘 3. 휴가 복귀일: 금요일' 와 같은 명령을 할 수 있습니다."
        },
    }),
    async created() {
        await this.init();

        this.generator = new ChatGenerator(this, {
            isStream: true,
            preferredLanguage: "Korean"
        });
    },
    watch: {
        "$route": {
            deep: true,
            async handler(newVal, oldVal) {
                if (newVal.path !== oldVal.path) {
                    await this.init();
                }
            }
        },
    },
    methods: {
        async loadData(path) {
            let value = await this.getData(path);
            this.checkDisableChat(value);

            let org = await this.getData("organization");
            
            if (org.organizationChart) {
                this.organizationChart = JSON.parse(org.organizationChart);
                
                if (!this.organizationChart) {
                    this.organizationChart = []
                }
            }
        },

        checkDisableChat(value) {
            if (value.status && value.status == "Completed") {
                this.disableChat = true;
            }

            if (value.currentUserId && value.currentUserId !== this.userInfo.email) {
                this.disableChat = true;
            }
        },

        async beforeSendMessage(newMessage) {
            try {
                if(!this.generator.contexts) {
                    let contexts = await this.queryFromVectorDB(newMessage);
                    this.generator.setContexts(contexts);
                }

                this.sendMessage(newMessage);

            } catch (error) {
                console.log(error);
            }
        },

        afterModelCreated(response) {
            let jsonInstance = this.extractJSON(response);

            if (jsonInstance) {
                try {
                    this.processInstance = partialParse(jsonInstance);

                } catch (error) {
                    this.processInstance = jsonInstance;

                    console.log(error);
                }
            }
        },

        async afterGenerationFinished() {
            if (this.processInstance) {
                if (typeof this.processInstance === "string") {
                    this.processInstance = partialParse(this.processInstance);
                }

                let contexts = await this.queryFromVectorDB(this.processInstance.processDefinitionId);
                if (contexts && contexts.length > 0) {
                    const jsonText = contexts.find(context => {
                        const definition = partialParse(context);
                        return definition.processDefinitionId == this.processInstance.processDefinitionId
                    });

                    this.processDefinition = partialParse(jsonText);
                }

                this.saveInstance();
                this.sendTodolist();
            }
        },

        async saveInstance(status) {
            if (this.processInstance && this.processDefinition) {
                let path = `${this.path}/${this.processInstance.processInstanceId}`;
                let putObj = await this.getData(path);

                if (putObj) {
                    await this.delete(path);

                    putObj.messages = this.messages;
                    putObj.currentUserId = this.processInstance.currentUserEmail;
                    putObj.currentActivityId = this.processInstance.currentActivityId;
                    putObj.nextUserId = this.processInstance.nextUserEmail;
                    putObj.nextActivityId = this.processInstance.nextActivityId;

                    let newParticipants = [ this.processInstance.currentUserEmail, this.processInstance.nextUserEmail ];
                    newParticipants = [
                        ...putObj.participants,
                        ...newParticipants
                    ];
                    const set = new Set(newParticipants);
                    putObj.participants = [...set];

                    if (status) {
                        putObj.status = status;
                    }

                } else {
                    putObj = {
                        messages: this.messages,
                        definitionId: this.processDefinition.processDefinitionId,
                        currentUserId: this.processInstance.currentUserEmail,
                        currentActivityId: this.processInstance.currentActivityId,
                        nextUserId: this.processInstance.nextUserEmail,
                        nextActivityId: this.processInstance.nextActivityId,
                        participants: [
                            this.processInstance.currentUserEmail, 
                            this.processInstance.nextUserEmail
                        ],
                        status: "Running",
                    };

                }
                
                await this.putObject(path, putObj);
            }
        },

        async sendTodolist() {
            if (this.processInstance && this.processDefinition) {
                if (this.processInstance.currentUserEmail !== "" 
                    //&& this.checkUserEmail(this.processInstance.currentUserEmail)
                ) {
                    let path = `todolist/${this.processInstance.currentUserEmail}`;
                    const pushObj = {
                        definitionId: this.processDefinition.processDefinitionId,
                        instanceId: this.processInstance.processInstanceId,
                        activityId: this.processInstance.currentActivityId,
                        userId: this.processInstance.currentUserEmail,
                        status: "Completed",
                        endDate: new Date().toISOString().substr(0, 10),
                    };
                    
                    const workItem = await this.checkTodolist(path, pushObj.activityId);
                    if (workItem) {
                        pushObj.startDate = workItem.startDate;
                        await this.delete(`${path}/${workItem.key}`);
                    }
                    
                    const actIdx = this.processDefinition.activities.findIndex(activity => 
                        activity.id == pushObj.activityId
                    );
                    if (actIdx < 1) {
                        pushObj.startDate = new Date().toISOString().substr(0, 10);
                    }

                    await this.pushObject(path, pushObj);
                }
                

                if (this.processInstance.nextUserEmail !== "" 
                    && this.checkUserEmail(this.processInstance.nextUserEmail)
                ) {
                    const path = `todolist/${this.processInstance.nextUserEmail}`;
                    const pushObj = {
                        definitionId: this.processDefinition.processDefinitionId,
                        instanceId: this.processInstance.processInstanceId,
                        activityId: this.processInstance.nextActivityId,
                        userId: this.processInstance.nextUserEmail,
                        status: "Running",
                        startDate: new Date().toISOString().substr(0, 10),
                    };

                    const actIdx = this.processDefinition.activities.findIndex(activity => 
                        activity.id == pushObj.activityId
                    );

                    await this.pushObject(path, pushObj);
                } else {
                    //NOTE: 이런 메시지를 주고 적절한 조치를 유도해야 합니다. "절대로" 그냥 먹으면 안됩니다.
                    if (this.processInstance.nextActivityId) {
                        alert("다음 담당자가 조직도상에 없습니다. 담당자를 다시 지정해주시거나 담당자를 등록해주세요");
                    } else {
                        this.saveInstance("Completed");
                    }
                }
            }
        },

        async queryFromVectorDB(messsage){
            const apiToken = this.generator.getToken();
            const vectorStore = new VectorStorage({ openAIApiKey: apiToken });

            // Perform a similarity search
            const results = await vectorStore.similaritySearch({
                query: messsage
            });

            if (results.similarItems) {
                return results.similarItems.map(item => item.text);
            }
        },

        async checkTodolist(path, actId) {
            let workItem;
            let todolist = await this.getData(path);
            if (todolist) {
                todolist = Object.values(todolist);
                todolist.forEach(item => {
                    if (item.activityId == actId) {
                        workItem = item;
                    }
                })
            }
            return workItem;
        },

        //NOTE: 조직도에 다음 담당자가 없으면 진행오류를 내야 합니다. 그냥 먹으면 안됩니다.
        checkUserEmail(email) {
            const checked = this.organizationChart.some(user => user.email == email);
            return checked;
        },

    }
}
</script>
