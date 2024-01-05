<script>
import partialParse from "partial-json-parser";

import CommonStorageBase from "@/components/storage/CommonStorageBase";

export default {
    data: () => ({
        storage: null,
        generator: null,
        messages: [],
        userInfo: {},
        chatDialog: false,
    }),
    methods: {
        async init() {
            this.test()

            this.storage = new CommonStorageBase(this);
            this.userInfo = await this.storage.getUserInfo();
            await this.loadData(this.getDataPath())
            this.messages = await this.loadMessages(this.getDataPath())
        },

        test(){
            
            let json = this.extractJSON(

            `
                네, 그럼 홍길동님의 정보와 관리팀, 개발팀에 대한 정보를 반영하여 조직도를 생성하겠습니다. 

                조직도는 다음과 같습니다: 

                \`\`\`
                {
                    "organizationChart": [
                        {
                            "team": true,
                            "id": "1",
                            "name": "개발팀", 
                            "description": "회사의 모든 개발 업무를 담당하는 팀"
                        },
                        {
                            "team": true,
                            "id": "2",
                            "name": "관리팀", 
                            "description": "회사의 관리
                            
                
                `
            
            )
            console.log("ChatModel test:", json)
            console.log("ChatModel test: partial parsed:", partialParse(json))
        },

        getDataPath(){
            return this.$route.href.replace("#/", "");
        },

        async loadData(path){

        },
    
        async loadMessages(path) {
            let value;
            if (path) {
                value = await this.storage.getObject(`db://${path}`);
            } else {
                value = await this.storage.getObject(`db://${this.path}`);
            }
    
            if (value && value.messages) {
                return JSON.parse(value.messages);
            } else {
                return this.messages;
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
    
        async sendMessage(message) {
            if (message !== "") {
                const chatObj = {
                    role: "user",
                    content: message
                }
                this.messages.push(chatObj);

                this.generator.previousMessages = [
                    ...this.generator.previousMessages,
                    ...this.messages
                ];
    
                await this.generator.generate();
    
                this.messages.push({
                    role:'system',
                    content: '...',
                    isLoading: true,
                });
            }
        },

        async editSendMessage(index) {
            if (index) {
                this.messages.splice(index);

                this.generator.previousMessages = [
                    ...this.generator.previousMessages,
                    ...this.messages
                ];

                await this.generator.generate();

                this.messages.push({
                    role:'system',
                    content: '...',
                    isLoading: true,
                });
            }
        },
    
        async putObject(path, obj) {
            await this.storage.putObject(`db://${path}`, obj);
        },

        async pushObject(path, obj) {
            await this.storage.pushObject(`db://${path}`, obj);
        },

        async setObject(path, obj) {
            await this.storage.setObject(`db://${path}`, obj);
        },
    
        onModelCreated(response) {
            let messageWriting = this.messages[this.messages.length -1];
            messageWriting.content = response;
    
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
                let messageWriting = this.messages[this.messages.length -1];
                delete messageWriting.isLoading;
                messageWriting.content = error.message;
            }
        },

        toggleChatDialog() {
            this.chatDialog = !this.chatDialog;
        },

        extractProcessJson(text) {            
            let textAndJson = text.split("--- json ---");
            if(textAndJson && textAndJson.length==2) {
                return textAndJson[1];
            }
        },

        hasUnclosedTripleBackticks(inputString) {
            // 백틱 세 개의 시작과 끝을 찾는 정규 표현식
            const regex = /`{3}/g;
            let match;
            let isOpen = false;

            // 모든 백틱 세 개의 시작과 끝을 찾습니다
            while ((match = regex.exec(inputString)) !== null) {
                // 현재 상태를 토글합니다 (열림 -> 닫힘, 닫힘 -> 열림)
                isOpen = !isOpen;
            }

            // 마지막으로 찾은 백틱 세 개가 닫혀있지 않은 경우 true 반환
            return isOpen;
        },

        extractJSON(inputString) {
            if(this.hasUnclosedTripleBackticks(inputString)){
                inputString = inputString + "\n```"
            }

            // 정규 표현식 정의
            const regex = /^.*?`{3}(?:json)?\n(.*?)`{3}.*?$/s;

            // 정규 표현식을 사용하여 입력 문자열에서 JSON 부분 추출
            const match = inputString.match(regex);

            // 매치된 결과가 있다면, 첫 번째 캡쳐 그룹(즉, JSON 부분)을 반환
            if (match) {
                return match[1];
            }

            // 매치된 결과가 없으면 null 반환
            return null;
        },

        // extractJSON(text) {            
        //     const regex = /```json\s*([\s\S]*?)(?:\n\s*```|$)/;
        //     const match = text.match(regex);
        //     return match ? match[1].trim() : null;
        // },
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

        uuid() {
            function s4() {
                return Math.floor((1 + Math.random()) * 0x10000)
                    .toString(16)
                    .substring(1);
            }

            return s4() + s4() + '-' + s4() + '-' + s4() + '-' +
                s4() + '-' + s4() + s4() + s4();
        },
    },
}
</script>