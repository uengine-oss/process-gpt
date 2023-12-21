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
        processInstance: null,
        bpmn: null,
        path: "instances",
        organizationChart: [],
        definitions: [],
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
                this.definitions = contexts;
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
                    console.log(error)
                }
            }
        },

        afterGenerationFinished(putObj) {
            let modelText = "";
            let path = this.path;
            console.log(this.definitions);
            
            if (this.processInstance) {
                if (typeof this.processInstance === "string") {
                    this.processInstance = partialParse(this.processInstance);
                }
                path = `${this.path}/${this.processInstance.processInstanceId}`;
                modelText = JSON.stringify(this.processInstance);
            }            

            putObj.model = modelText;

            this.saveMessages(path, putObj);

            this.sendTodolist(putObj);
        },

        async sendTodolist() {
            const userInfo = await this.storage.getUserInfo();
            const path = `todolist/${userInfo.name}`;
            let putObj = {};
            let newId = this.uuid();

            if (this.processInstance) {
                putObj[newId] = {
                    activityId: this.processInstance.currentActivityId,
                    activityName: this.processInstance.currentActivityId,
                    startDate: "",
                    endDate: "",
                    dueDate: "",
                    processDefinitionId: this.processInstance.processDefinitionId,
                    processInstanceId: this.processInstance.processInstanceId,
                    userId: this.processInstance.currentUserEmail
                }
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
