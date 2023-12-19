<template>
    <div>
        <v-card class="chat-open-box">
            <!-- <v-alert
                    type="info"
                    color="deep-purple-accent-4"
                    title="조직도 관리"
                    text="대화형으로 조직도를 관리하십시오.
                    팀(부서) 롤(역할), 직원들을 등록 수정 삭제할 수 있습니다. 예를 들어, 'OOO님을 신입사원으로 관리팀에 등록해줘. 이메일 주소는 new@company.com 이야. 역할은 개발자로 들어오셨어.'와 같은 명령을 할 수 있습니다."
            ></v-alert> -->

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
                        autofocus
                        auto-grow
                >
                    <template v-slot:append-inner>
                        <v-btn @click="send"
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
export default {
    props: {
        messages: Array,
    },
    data() {
        return {
            newMessage: "",
        }
    },
    methods: {
        send() {
            this.$emit('sendMessage', this.newMessage);
            this.newMessage = "";
        }
    }
}
</script>

<style scoped>
.chat-open-box {
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
    max-height: 74vh;
}

.chat-box {
    position: absolute;
    bottom: 0px;
    right: 0px;
    width: 100%;
}
</style>