<script>
import CommonStorageBase from "@/components/storage/CommonStorageBase";

export default {
    data: () => ({
        storage: null,
        value: null,
        generator: null,
        messages: []
    }),
    methods: {
        async init() {
            this.storage = new CommonStorageBase(this);
        },
    
        async loadMessages(path) {
            if (path) {
                this.value = await this.storage.getObject(`db://${path}`);
            } else {
                this.value = await this.storage.getObject(`db://${this.path}`);
            }
    
            if (this.value) {
                await this.loadData();
    
                if (this.value.messages) {
                    this.messages = JSON.parse(this.value.messages);
    
                    if (!this.messages) {
                        this.messages = [];
                    }
                }
    
                this.generator.previousMessages = [...this.generator.previousMessages, ...this.messages];
            }
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
    
            if (response.includes("\n")) {
                messageWriting.content = response.replace(/\n/g, "<br/>");
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
        }
    },
}
</script>