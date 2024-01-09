<template>
    <div>
        <v-btn @click="toggleChatDialog"
                icon
                class="chat-btn"
        >
            <v-icon v-if="chatDialog">mdi-close</v-icon>
            <v-icon v-else>mdi-chat</v-icon>
        </v-btn>

        <v-card v-if="chatDialog" width="500" class="chat-dialog">
            <Chat :messages="messages"
                    :disableChat="disableChat"
                    @sendMessage="beforeSendMessage"
                    @sendEditedMessage="sendEditedMessage"
            >
                <template v-slot:alert>
                    <v-alert
                            icon="mdi-info"
                            :title="alertInfo.title"
                            :text="alertInfo.text"
                    ></v-alert>
                </template>
            </Chat>
        </v-card>
    </div>
</template>

<script>
import Chat from "../ui/Chat.vue";

export default {
    props: {
        chatDialog: Boolean,
        messages: Array,
        alertInfo: Object,
        disableChat: Boolean,
    },
    components: {
        Chat,
    },
    methods: {
        toggleChatDialog() {
            this.$emit("toggleChatDialog");
        },
        beforeSendMessage(message) {
            this.$emit("beforeSendMessage", message);
        },
        sendEditedMessage(index) {
            this.$emit("sendEditedMessage", index);
        }
    }
}
</script>

<style scoped>
.chat-btn {
    position: absolute;
    bottom: 20px;
    right: 20px;
}

.chat-dialog {
    z-index: 999;
    position: absolute;
    bottom: 90px;
    right: 20px;
}
</style>