<template>
    <div>
        <v-card class="chat-open-box">
            <v-alert
                    type="info"
                    color="deep-purple-accent-4"
                    title="조직도 관리"
                    text="대화형으로 조직도를 관리하십시오.
                    팀(부서) 롤(역할), 직원들을 등록 수정 삭제할 수 있습니다. 예를 들어, 'OOO님을 신입사원으로 관리팀에 등록해줘. 이메일 주소는 new@company.com 이야. 역할은 개발자로 들어오셨어.'와 같은 명령을 할 수 있습니다."
            ></v-alert>

            <v-card-text class="message-box">
                <div v-for="(message, index) in messages"
                        :key="index"
                >
                    <div v-if="message.role == 'user'"
                            class="d-flex justify-end my-2"
                    >
                        <v-sheet class="user-message pa-3"
                                color="primary"
                        >
                            <div v-html="message.content"></div>
                        </v-sheet>
                        <div class="ml-2">
                            <v-avatar size="48">
                                <v-icon>
                                    mdi-account-circle
                                </v-icon>
                            </v-avatar>
                            <div class="subtitle-2 text-center">
                                User
                            </div>
                        </div>
                    </div>

                    <div v-else-if="message.role == 'system'"
                            class="d-flex justify-start my-2"
                    >
                        <div class="mr-2">
                            <v-avatar size="48">
                                <v-icon>
                                    mdi-account-circle
                                </v-icon>
                            </v-avatar>
                            <div class="subtitle-2 text-center">
                                System
                            </div>
                        </div>
                        <v-sheet class="system-message pa-3"
                                color="grey-200"
                        >
                            <v-progress-circular
                                    v-if="message.isLoading"
                                    indeterminate
                                    color="grey"
                            ></v-progress-circular>
                            <div v-html="message.content"></div>
                        </v-sheet>
                    </div>
                </div>
            </v-card-text>

            <v-card-actions class="chat-box">
                <v-textarea
                        v-model="newMessage"
                        label="Send Message"
                        rows="1"
                        auto-grow
                        autofocus
                >
                    <template v-slot:append-inner>
                        <v-btn @click="sendMessage"
                                color="primary"
                                icon
                                small
                        >
                            <v-icon>mdi-send</v-icon>
                        </v-btn>
                    </template>
                </v-textarea>
            </v-card-actions>
        </v-card>
    </div>
</template>

<script>
import ChatGenerator from "./ai/OrganizationChartGenerator.js";

export default {
    name: 'OrganizationChartChat',
    components: {
    },
    data: () => ({
        messages: [],
        newMessage: "",
        generator: null,
        loading: false,
    }),
    created() {
        this.generator = new ChatGenerator(this, {
            isStream: true,
            preferredLanguage: "Korean"
        });
        this.init();
    },
    methods:{
        init() {
            this.loadMessages();
        },

        sendMessage() {
            if (this.newMessage !== "") {
                if(this.newMessage.includes("\n")) {
                    this.newMessage = this.newMessage.replace(/\n/g, "<br/>");
                }

                this.init();
                
                this.messages.push(
                    {
                        role: "user",
                        content: this.newMessage
                    }
                );

                this.generator.generate();
    

                this.messages.push({
                    role:'system',
                    content: '...',
                    isLoading: true,
                });

                this.newMessage = "";

                this.saveMessages()
            }
        },

        onModelCreated(response){
            let messageWriting = this.messages[this.messages.length -1];
            messageWriting.content = response;

            if (response.includes("\n")) {
                messageWriting.content = response.replace(/\n/g, "<br/>");
            }
        },


        onGenerationFinished(responses) {
            // console.log(responses);
            let messageWriting = this.messages[this.messages.length -1];
            delete messageWriting.isLoading;

            this.saveMessages();
        },

        onError(error) {
            if (error.code === "invalid_api_key") {
                var apiKey = prompt("API Key 를 입력하세요.");
                localStorage.setItem("openAIToken", apiKey);
                
                this.generator.generate();
                
            } else {
                console.log(error)
                var message = {
                    role:'system',
                    content: error.message
                };

                this.messages.push(message);
            }
        },

        saveMessages() {
            window.localStorage.setItem("organization-chart-conversation", JSON.stringify(this.messages));
        },
        
        loadMessages() {
            this.messages = JSON.parse(window.localStorage.getItem("organization-chart-conversation"));
            if (!this.messages) {
                this.messages = [];
            }
            this.generator.previousMessages = [...this.generator.previousMessages, ...this.messages];

            // console.log(this.generator.previousMessages);
        },

    }
}
</script>

<style scoped>
.chat-open-box {
    /* z-index: 999; */
    min-height: 84vh;
}

.user-message {
    border-radius: 20px;
    max-width: 95%;
}

.system-message {
    border-radius: 20px;
    max-width: 95%;
}

.message-box {
    overflow-y: auto;
    max-height: 60vh;
}

.chat-box {
    position: absolute;
    bottom: 0px;
    right: 0px;
    width: 100%;
}

</style>