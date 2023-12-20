<script>
import CommonStorageBase from "@/components/storage/CommonStorageBase";

export default {
    data: () => ({
        storage: null,
        generator: null,
        messages: []
    }),
    methods: {
        async init() {
            this.storage = new CommonStorageBase(this);
        },
    
        async loadMessages(path) {
            let value;
            if (path) {
                value = await this.storage.getObject(`db://${path}`);
            } else {
                value = await this.storage.getObject(`db://${this.path}`);
            }
    
            if (value) {
                if (value.messages) {
                    this.messages = JSON.parse(value.messages);
    
                    if (!this.messages) {
                        this.messages = [];
                    }
                }
   
                this.generator.previousMessages = [
                    ...this.generator.previousMessages,
                    ...this.messages
                ];
            }
        },

        async getData(path) {
            let value;
            if (path) {
                value = await this.storage.getObject(`db://${path}`);
            } else {
                value = await this.storage.getObject(`db://${this.path}`);
            }
            return value;
        },
    
        sendMessage(message) {
            if (message !== "") {
                if(message.includes("\n")) {
                    message = message.replace(/\n/g, "<br/>");
                }
                
                this.messages.push({
                    role: "user",
                    content: message
                });

                this.generator.previousMessages = [
                    ...this.generator.previousMessages,
                    ...this.messages
                ];
    
                this.generator.generate();
    
                this.messages.push({
                    role:'system',
                    content: '...',
                    isLoading: true,
                });
            }
        },
    
        async saveMessages(path, obj) {
            await this.storage.putObject(`db://${path}`, obj);
        },
    
        onModelCreated(response) {
            let messageWriting = this.messages[this.messages.length -1];
            messageWriting.content = response;
    
            if (messageWriting.content.includes("\n")) {
                messageWriting.content = messageWriting.content.replace(/\n/g, "<br/>");
            }

            if (response.match(/<[^>]*>?/g)) {
                response = response.replace(/<[^>]*>?/g, "");
            }
            this.afterModelCreated(response);
        },
    
        onGenerationFinished(responses) {
            // console.log(responses);
            let messageWriting = this.messages[this.messages.length -1];
            delete messageWriting.isLoading;
    
            var msgText = "";
            if (this.messages) {
                msgText = JSON.stringify(this.messages);
            }
    
            var putObj =  {
                messages: msgText,
            }
    
            this.afterGenerationFinished(putObj);
        },
    
        onError(error) {
            if (error.code === "invalid_api_key") {
                var apiKey = prompt("API Key 를 입력하세요.");
                localStorage.setItem("openAIToken", apiKey);
                
                this.generator.generate();
                
            } else {
                var message = {
                    role:'system',
                    content: error.message
                };
    
                this.messages.push(message);
            }
        },

        extractProcessJson(text) {            
            let textAndJson = text.split("--- json ---")
            if(textAndJson && textAndJson.length==2) return textAndJson[1]
        },
        extractJSON(text) {            
            const regex = /```json\s*([\s\S]*?)(?:\n\s*```|$)/;
            const match = text.match(regex);
            return match ? match[1].trim() : null;
        },
        extractXML(text) {            
            const regex = /```xml\s*([\s\S]*?)(?:\n\s*```|$)/;
            const match = text.match(regex);
            return match ? match[1].trim() : null;
        },
        extractBPMN(text) {
            const regex = /```bpmn\s*([\s\S]*?)(?:\n\s*```|$)/;
            const match = text.match(regex);
            return match ? match[1].trim() : null;
        },
        extractCode(text) {
            const regex = /```\s*([\s\S]*?)(?:\n\s*```|$)/;
            const match = text.match(regex);
            return match ? match[1].trim() : null;
        },
    },
}
</script>