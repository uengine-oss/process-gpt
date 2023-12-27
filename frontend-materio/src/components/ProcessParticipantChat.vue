<template>
    <div>
        <process-definition
                v-if="bpmn"
                :bpmn="bpmn"
        ></process-definition>

        <Chat :messages="messages"
                @sendMessage="beforeSendMessage"
        />
    </div>
</template>

<script>
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage";

import ChatGenerator from "./ai/ProcessInstanceGenerator.js";

import ChatModule from "./ChatModule.vue";
import Chat from "./Chat.vue"


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
    }),
    async created() {
        this.init();

        await this.loadData("organization");

        this.generator = new ChatGenerator(this, {
            isStream: true,
            preferredLanguage: "Korean"
        });

        var path = this.$route.href.replace("#/", "");
        if (this.$route.params && this.$route.params.id) {
            this.loadMessages(path);
        } else {
            this.loadMessages();
        }
        this.loadData(path);
    },
    watch: {
        "$route": {
            deep: true,
            async handler(newVal, oldVal) {
                if (newVal.path !== oldVal.path) {
                    this.bpmn = null;

                    var path = this.$route.href.replace("#/", "");
                    await this.loadMessages(path);
                    this.loadData(path);
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

                    } else {
                        this.messages = [];
                        
                        var list = Object.values(value);
                        list.forEach(item => {
                            const msg = JSON.parse(item.messages);
                            this.messages = [...this.messages, ...msg];
                        });

                        this.generator.previousMessages = [
                            ...this.generator.previousMessages,
                            ...this.messages
                        ];
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
            let path = this.path;
    
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
            }

            putObj.model = modelText;

            this.saveMessages(path, putObj);

            this.sendTodolist();
        },

        async sendTodolist() {
            const userInfo = await this.storage.getUserInfo();
            const path = `todolist/${userInfo.name}`;
            const newId = this.uuid();
            let putObj = {};

            putObj[newId] = {
                activityId: "",
                activityName: "",
                startDate: new Date().toISOString().substr(0, 10),
                endDate: "",
                dueDate: "",
                processDefinitionId: "",
                processInstanceId: "",
                userId: ""
            };

            if (this.processInstance) {
                putObj[newId].activityId = this.processInstance.currentActivityId;
                putObj[newId].processInstanceId = this.processInstance.processInstanceId;
                putObj[newId].userId = this.processInstance.currentUserEmail;
            }

            if (this.processDefinition) {
                putObj[newId].processDefinitionId = this.processDefinition.processDefinitionId;

                this.processDefinition.activities.forEach(act => {
                    if (act.id == this.processInstance.currentActivityId) {
                        putObj[newId].activityName = act.name; 
                    }
                });
            }

            this.saveMessages(path, putObj);
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

        uuid() {
            function s4() {
                return Math.floor((1 + Math.random()) * 0x10000)
                    .toString(16)
                    .substring(1);
            }

            return s4() + s4() + '-' + s4() + '-' + s4() + '-' +
                s4() + '-' + s4() + s4() + s4();
        },

    }
}
</script>
