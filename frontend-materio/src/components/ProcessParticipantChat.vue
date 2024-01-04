<template>
    <div>
        <chat :messages="messages"
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
        </chat>
    </div>
</template>

<script>
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage";

import ChatGenerator from "./ai/ProcessInstanceGenerator.js";
import Chat from "./ui/Chat.vue";

import ChatModule from "./ChatModule.vue";


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
        bpmn: null,
        path: "instances",
        organizationChart: [],
        alertInfo: {
            title: "프로세스 실행",
            text: "대화형으로 프로세스를 실행하십시오. 예를 들어, '휴가를 신청할게: 1. 사유: 개인사유 2. 휴가 시작일: 오늘 3. 휴가 복귀일: 금요일' 와 같은 명령을 할 수 있습니다."
        },
    }),
    async created() {
        this.init();

        await this.loadData("organization");

        this.generator = new ChatGenerator(this, {
            isStream: true,
            preferredLanguage: "Korean"
        });

        var path = this.$route.href.replace("#/", "");
        this.loadData(path);

        this.messages = await this.loadMessages(path);
    },
    watch: {
        "$route": {
            deep: true,
            async handler(newVal, oldVal) {
                if (newVal.path !== oldVal.path) {
                    this.bpmn = null;
                    var path = this.$route.href.replace("#/", "");
                    this.loadData(path);

                    this.messages = await this.loadMessages(path);
                }
            }
        }
    },
    methods: {
        async loadData(path) {
            const value = await this.getData(path);

            if (value) {
                if (value.organizationChart) {
                    this.organizationChart = JSON.parse(value.organizationChart);
                    
                    if (!this.organizationChart) {
                        this.organizationChart = []
                    }
                } else {
                    if (this.$route.params && this.$route.params.id) {
                        var jsonInstance = partialParse(value.model);
                        if (jsonInstance) {
                            this.processInstance = jsonInstance;
                        }

                    }
                }
            }
        },

        async beforeSendMessage(newMessage) {
            if(!this.generator.contexts) {
                let contexts = await this.queryFromVectorDB(newMessage);
                this.generator.setContexts(contexts);
            }

            this.sendMessage(newMessage);
        },

        afterModelCreated(response) {
            let jsonInstance = this.extractProcessJson(response);

            if (jsonInstance) {
                try {
                    this.processInstance = partialParse(jsonInstance);
                } catch (error) {
                    this.processInstance = jsonInstance;
                    console.log(error);
                }
            }
        },

        async afterGenerationFinished(putObj) {
            let modelText = "";
            let path = "";
    
            if (this.processInstance) {
                if (typeof this.processInstance === "string") {
                    this.processInstance = partialParse(this.processInstance);
                }
                path = `${this.path}/${this.processInstance.processInstanceId}`;
                modelText = JSON.stringify(this.processInstance);

                let contexts = await this.queryFromVectorDB(this.processInstance.processDefinitionId);
                if (contexts && contexts.length > 0) {
                    contexts.forEach(item => {
                        this.processDefinition = partialParse(item);
                    });
                }

                putObj.model = modelText;

                this.saveMessages(path, putObj);

                this.sendTodolist();
            }
        },

        async sendTodolist() {
            let path = "";
            const uuid = this.uuid();
            let putObj = {};

            putObj[uuid] = {
                activityId: "",
                activityName: "",
                startDate: new Date().toISOString().substr(0, 10),
                endDate: "",
                dueDate: "",
                processDefinitionId: "",
                processInstanceId: "",
                userId: this.userInfo.email
            };

            if (this.processDefinition) {
                putObj[uuid].processDefinitionId = this.processDefinition.processDefinitionId;

                this.processDefinition.activities.forEach(act => {
                    if (act.id == this.processInstance.currentActivityId) {
                        putObj[uuid].activityName = act.name; 
                    }
                });
            }

            if (this.processInstance) {
                putObj[uuid].activityId = this.processInstance.currentActivityId;
                putObj[uuid].processInstanceId = this.processInstance.processInstanceId;
                path = `todolist/${this.processInstance.nextUserEmail}`;
                
                this.saveMessages(path, putObj);
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

    }
}
</script>
