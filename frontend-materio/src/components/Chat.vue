<template>
    <div>
        <v-card class="chat-open-box">
            <v-card-text class="message-box pa-0">
                <!-- slot -->
                <slot name="alert"></slot>
                
                <div v-for="(message, index) in filteredMessages"
                        :key="index"
                        class="pa-3"
                >
                    <div v-if="message.role == 'user'"
                            class="d-flex justify-end my-2"
                    >
                        <v-sheet class="user-message pa-3"
                                color="primary"
                        >
                            <pre>{{ message.content }}</pre>
                        </v-sheet>
                        <div class="ml-2">
                            <v-avatar size="48">
                                <v-icon>
                                    mdi-account-circle
                                </v-icon>
                            </v-avatar>
                            <div class="subtitle-2 text-center">
                                {{ message.role }}
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
                            <pre>{{ message.content }}</pre>
                        </v-sheet>
                        <v-progress-circular
                                v-if="message.isLoading"
                                indeterminate
                                color="grey"
                                class="ml-2 mt-2"
                        ></v-progress-circular>
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
    computed: {
        filteredMessages() {
            var list = [];
            this.messages.forEach(item => {
                const data = JSON.parse(JSON.stringify(item));
                list.push(data);
            });
            return list
        }
    },
    mounted() {
        window.addEventListener("keydown", (evt) => {
            if (evt.ctrlKey && evt.keyCode == 67) {
                let selectedObj = window.getSelection();
                if (selectedObj) {
                    let selected = selectedObj.getRangeAt(0).toString();
                }
            }
        });
    },
    methods: {
        send() {
            this.$emit('sendMessage', this.newMessage);
            this.newMessage = "";
        },
    }
}
</script>

<style scoped>
.chat-open-box {
    height: calc(100vh - 112px);
    max-height: calc(100vh - 112px);
}

.user-message {
    border-radius: 20px;
    max-width: 90%;
}

.system-message {
    border-radius: 20px;
    max-width: 90%;
}

pre {
    font-family: inter, sans-serif, -apple-system, blinkmacsystemfont, "Segoe UI", roboto, "Helvetica Neue", arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";
    font-size: 0.875rem !important;
    letter-spacing: 0.0094rem !important;
    overflow: auto;
    white-space: pre-wrap;
}

.message-box {
    overflow-y: auto;
    max-height: calc(100% - 65px);
}

.chat-box {
    position: absolute;
    bottom: 0px;
    right: 0px;
    width: 100%;
}
</style>