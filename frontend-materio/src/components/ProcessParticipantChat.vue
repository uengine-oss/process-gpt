<template>
    <div>
        <v-card class="chat-open-box">
            <v-card-text class="message-box" ref="messages">
                <div v-for="(message, index) in messages"
                        :key="index"
                >
                    <div v-if="message.role == 'user'"
                            class="d-flex justify-end my-2"
                    >
                        <div class="user-message">
                            {{ message.content }} 
                        </div>
                        <div class="ml-1">
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
                                {{ message.role }}
                            </div>
                        </div>
                        <div class="d-flex system-message">
                            <div v-html="message.content"></div>
                        </div>
                        <br>
                        <vue-bpmn v-if="message.bpmn" :key="message.bpmn.length"
                                :bpmn="message.bpmn"
                                :options="options"
                                v-on:error="handleError"
                                v-on:shown="handleShown"
                                v-on:loading="handleLoading"
                            ></vue-bpmn>
                    </div>
                </div>

                <div v-if="loading" class="d-flex justify-start my-2">
                    <div class="mr-2">
                        <v-avatar size="48">
                            <v-icon>
                                mdi-account-circle
                            </v-icon>
                        </v-avatar>
                        <div class="subtitle-2 text-center">
                            system
                        </div>
                    </div>
                    <div class="d-flex system-message">
                        <v-progress-circular
                                indeterminate
                                color="grey"
                        ></v-progress-circular>
                    </div>
                </div>
            </v-card-text>

            <v-card-actions class="chat-box">
                <!-- <vue-bpmn 
                        :bpmn="bpmn"
                        :options="options"
                        v-on:error="handleError"
                        v-on:shown="handleShown"
                        v-on:loading="handleLoading"
                ></vue-bpmn> -->
            
                <v-textarea
                        v-model="newMessage"
                        @keydown.enter="sendMessage"
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
import ChatGenerator from "./ai/ProcessInstanceGenerator.js";

import BaseRepository from "./repository/BaseRepository";
import axios from "@axios";
import VueBpmn from './Bpmn.vue';
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage"

export default {
    name: 'ProcessParticipantChat',
    components: {
        VueBpmn
    },
    data: () => ({
        messages: [],
        newMessage: "",
        generator: null,
        loading: false,
        openChatBox: false,
        bpmn: `
<?xml version="1.0" encoding="UTF-8"?><bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" xmlns:di="http://www.omg.org/spec/DD/20100524/DI" id="Definitions_1" targetNamespace="http://bpmn.io/schema/bpmn" exporter="Custom BPMN Modeler" exporterVersion="1.0"><bpmn:process id="vacationRequestProcess" isExecutable="true"><bpmn:task id="vacationRequestActivity" name="휴가 신청"/><bpmn:task id="approvalActivity" name="휴가 신청 승인"/><bpmn:task id="remainingDaysActivity" name="휴가 잔여일 확인"/><bpmn:task id="notificationActivity" name="휴가 통지"/><bpmn:sequenceFlow id="SequenceFlow_vacationRequestActivity_approvalActivity" sourceRef="vacationRequestActivity" targetRef="approvalActivity"/><bpmn:sequenceFlow id="SequenceFlow_approvalActivity_remainingDaysActivity" sourceRef="approvalActivity" targetRef="remainingDaysActivity"/><bpmn:sequenceFlow id="SequenceFlow_remainingDaysActivity_notificationActivity" sourceRef="remainingDaysActivity" targetRef="notificationActivity"/></bpmn:process><bpmndi:BPMNDiagram id="BPMNDiagram_1"><bpmndi:BPMNPlane id="BPMNPlane_1" bpmnElement="vacationRequestProcess"><bpmndi:BPMNShape id="BPMNShape_vacationRequestActivity" bpmnElement="vacationRequestActivity"><dc:Bounds xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" x="100" y="100" width="100" height="80"/></bpmndi:BPMNShape><bpmndi:BPMNShape id="BPMNShape_approvalActivity" bpmnElement="approvalActivity"><dc:Bounds xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" x="250" y="100" width="100" height="80"/></bpmndi:BPMNShape><bpmndi:BPMNShape id="BPMNShape_remainingDaysActivity" bpmnElement="remainingDaysActivity"><dc:Bounds xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" x="400" y="100" width="100" height="80"/></bpmndi:BPMNShape><bpmndi:BPMNShape id="BPMNShape_notificationActivity" bpmnElement="notificationActivity"><dc:Bounds xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" x="550" y="100" width="100" height="80"/></bpmndi:BPMNShape><bpmndi:BPMNEdge id="BPMNEdge_vacationRequestActivity_approvalActivity" bpmnElement="SequenceFlow_vacationRequestActivity_approvalActivity"><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="150" y="140"/><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="250" y="140"/></bpmndi:BPMNEdge><bpmndi:BPMNEdge id="BPMNEdge_approvalActivity_remainingDaysActivity" bpmnElement="SequenceFlow_approvalActivity_remainingDaysActivity"><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="150" y="140"/><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="250" y="140"/></bpmndi:BPMNEdge><bpmndi:BPMNEdge id="BPMNEdge_remainingDaysActivity_notificationActivity" bpmnElement="SequenceFlow_remainingDaysActivity_notificationActivity"><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="150" y="140"/><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="250" y="140"/></bpmndi:BPMNEdge></bpmndi:BPMNPlane></bpmndi:BPMNDiagram></bpmn:definitions>        `
    }),
    created() {
        this.generator = new ChatGenerator(this, {
            isStream: true,
            preferredLanguage: "Korean"
        });
        this.init();
    },
    watch: {
        messages() {
            this.$nextTick(() => {
                let messages = this.$refs.messages;
                messages.scrollTo({ top: messages.scrollHeight, behavior: 'smooth' });
            });
        },
    },
    methods:{
        handleClick() {
            this.openChatBox = !this.openChatBox;
        },
        init() {
            this.loadMessages()
        },

        async sendMessage() {
            if (this.newMessage !== "") {
                this.loading = true;
                this.init();
                
                this.messages.push(
                    {
                        role: "user",
                        content: this.newMessage
                    }
                );

                if(!this.generator.contexts){
                    let contexts = await this.queryFromVectorDB(this.newMessage)
                    this.generator.setContexts(contexts)
                }

                this.generator.generate();
    

                this.messages.push({
                    role:'system',
                    content: '.'
                });

                this.newMessage = "";

                this.saveMessages()

            }
        },

        async queryFromVectorDB(messsage){
            const vectorStore = new VectorStorage({ openAIApiKey: this.generator.getToken() });

            // Perform a similarity search
            const results = await vectorStore.similaritySearch({
                query: messsage
            });

            console.log(results.similarItems)

            if(results.similarItems)
                return results.similarItems.map(item => item.text)
            
        },

        onModelCreated(response){

            let messageWriting = this.messages[this.messages.length -1]
            messageWriting.content = response

            let jsonProcess = this.extractJSON(response)
            if(!jsonProcess)
                jsonProcess = this.extractCode(response)
            if(response.startsWith("{")){
                jsonProcess = response
            }

            if(jsonProcess && jsonProcess.processDefinitionId){

                jsonProcess = partialParse(jsonProcess)
                messageWriting.content = jsonProcess.description
                this.processDefinition = jsonProcess

                messageWriting.bpmn = this.createBpmnXml(jsonProcess)
//messageWriting.bpmn = `<?xml version="1.0" encoding="UTF-8"?><bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" xmlns:di="http://www.omg.org/spec/DD/20100524/DI" id="Definitions_1" targetNamespace="http://bpmn.io/schema/bpmn" exporter="Custom BPMN Modeler" exporterVersion="1.0"><bpmn:process id="휴가신청프로세스" isExecutable="true"><bpmn:task id="휴가신청" name="휴가신청"/><bpmn:task id="휴가승인" name="휴가승인"/><bpmn:task id="허용여부통지" name="허용여부통지"/><bpmn:sequenceFlow id="SequenceFlow_휴가신청_휴가승인" sourceRef="휴가신청" targetRef="휴가승인"/><bpmn:sequenceFlow id="SequenceFlow_휴가승인_허용여부통지" sourceRef="휴가승인" targetRef="허용여부통지"/></bpmn:process><bpmndi:BPMNDiagram id="BPMNDiagram_1"><bpmndi:BPMNPlane id="BPMNPlane_1" bpmnElement="휴가신청프로세스"><bpmndi:BPMNShape id="BPMNShape_휴가신청" bpmnElement="휴가신청"><dc:Bounds xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" x="100" y="100" width="100" height="80"/></bpmndi:BPMNShape><bpmndi:BPMNShape id="BPMNShape_휴가승인" bpmnElement="휴가승인"><dc:Bounds xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" x="250" y="100" width="100" height="80"/></bpmndi:BPMNShape><bpmndi:BPMNShape id="BPMNShape_허용여부통지" bpmnElement="허용여부통지"><dc:Bounds xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" x="400" y="100" width="100" height="80"/></bpmndi:BPMNShape><bpmndi:BPMNEdge id="BPMNEdge_휴가신청_휴가승인" bpmnElement="SequenceFlow_휴가신청_휴가승인"><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="150" y="140"/><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="250" y="140"/></bpmndi:BPMNEdge><bpmndi:BPMNEdge id="BPMNEdge_휴가승인_허용여부통지" bpmnElement="SequenceFlow_휴가승인_허용여부통지"><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="150" y="140"/><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="250" y="140"/></bpmndi:BPMNEdge></bpmndi:BPMNPlane></bpmndi:BPMNDiagram></bpmn:definitions>`
            
                console.log(messageWriting.bpmn)

            }


        },

        createBpmnXml(jsonProcess) {
            // XML 문서 초기화
            const parser = new DOMParser();
            const xmlDoc = parser.parseFromString('<?xml version="1.0" encoding="UTF-8"?><bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" xmlns:bpmndi=\"http://www.omg.org/spec/BPMN/20100524/DI\"></bpmn:definitions>', 'application/xml');
            const bpmn = xmlDoc.documentElement;

            // XML 네임스페이스 설정
            bpmn.setAttribute('xmlns:bpmn', 'http://www.omg.org/spec/BPMN/20100524/MODEL');
            bpmn.setAttribute('xmlns:bpmndi', 'http://www.omg.org/spec/BPMN/20100524/DI');
            bpmn.setAttribute('xmlns:dc', 'http://www.omg.org/spec/DD/20100524/DC');
            bpmn.setAttribute('xmlns:di', 'http://www.omg.org/spec/DD/20100524/DI');
            bpmn.setAttribute('id', 'Definitions_1');
            bpmn.setAttribute('targetNamespace', 'http://bpmn.io/schema/bpmn');
            bpmn.setAttribute('exporter', 'Custom BPMN Modeler');
            bpmn.setAttribute('exporterVersion', '1.0');

            // Process 요소 생성
            const process = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:process');
            process.setAttribute('id', jsonProcess.processDefinitionId.replace(/\s+/g, '_'));
            process.setAttribute('isExecutable', 'true');

            // 각 활동 (Activity) 요소 생성
            if(jsonProcess.activities)
            jsonProcess.activities.forEach(activity => {
                const task = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:task');
                task.setAttribute('id', activity.id);
                task.setAttribute('name', activity.name);
                process.appendChild(task);
            });

            // 시퀀스 플로우 생성
            if(jsonProcess.sequences)
            jsonProcess.sequences.forEach(sequence => {
                const sequenceFlow = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:sequenceFlow');
                sequenceFlow.setAttribute('id', 'SequenceFlow_' + sequence.source + '_' + sequence.target);
                sequenceFlow.setAttribute('sourceRef', sequence.source);
                sequenceFlow.setAttribute('targetRef', sequence.target);
                process.appendChild(sequenceFlow);
            });

            bpmn.appendChild(process);

            // BPMNDiagram 요소 추가
            const bpmnDiagram = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNDiagram');
            bpmnDiagram.setAttribute('id', 'BPMNDiagram_1');
            const bpmnPlane = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNPlane');
            bpmnPlane.setAttribute('id', 'BPMNPlane_1');
            bpmnPlane.setAttribute('bpmnElement', process.getAttribute('id'));
            bpmnDiagram.appendChild(bpmnPlane);

            // 시각적 요소 생성 (BPMNShape 및 BPMNEdge)
            // 주의: 여기서는 간단한 예제로 위치와 크기를 고정값으로 설정합니다.

            if(jsonProcess.activities)
            jsonProcess.activities.forEach((activity, index) => {
                const shape = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNShape');
                shape.setAttribute('id', 'BPMNShape_' + activity.id);
                shape.setAttribute('bpmnElement', activity.id);

                const bounds = xmlDoc.createElementNS('http://www.omg.org/spec/DD/20100524/DC', 'dc:Bounds');
                bounds.setAttribute('x', 100 + (index * 150)); // 예제 위치
                bounds.setAttribute('y', 100);
                bounds.setAttribute('width', 100);
                bounds.setAttribute('height', 80);

                shape.appendChild(bounds);
                bpmnPlane.appendChild(shape);
            });

            // 시퀀스 플로우 시각적 요소
            if(jsonProcess.sequences)
            jsonProcess.sequences.forEach(sequence => {
                const edge = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNEdge');
                edge.setAttribute('id', 'BPMNEdge_' + sequence.source + '_' + sequence.target);
                edge.setAttribute('bpmnElement', 'SequenceFlow_' + sequence.source + '_' + sequence.target);

                // 예제 waypoint
                const waypoint1 = xmlDoc.createElementNS('http://www.omg.org/spec/DD/20100524/DI', 'di:waypoint');
                waypoint1.setAttribute('x', 150);
                waypoint1.setAttribute('y', 140);

                const waypoint2 = xmlDoc.createElementNS('http://www.omg.org/spec/DD/20100524/DI', 'di:waypoint');
                waypoint2.setAttribute('x', 250);
                waypoint2.setAttribute('y', 140);

                edge.appendChild(waypoint1);
                edge.appendChild(waypoint2);

                bpmnPlane.appendChild(edge);
            });

            bpmn.appendChild(bpmnDiagram);

            // XML 문자열로 변환
            const serializer = new XMLSerializer();
            const xmlString = serializer.serializeToString(xmlDoc);
            return xmlString;
        },

        extractJSON(text) {            
            const regex = /```xml\s*([\s\S]*?)(?:\n\s*```|$)/;
            const match = text.match(regex);
            return match ? match[1].trim() : null;
        },
        extractXML(text) {            
            const regex = /```json\s*([\s\S]*?)(?:\n\s*```|$)/;
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

        onGenerationFinished(responses){
            // console.log(responses);
            this.loading = false;
            var message;

            this.saveMessages()

        },

        onError(error) {
            this.loading = false;

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
        saveMessages(){
            window.localStorage.setItem("process-instance-conversation", JSON.stringify(this.messages))
        },
        loadMessages(){
            this.messages = JSON.parse(window.localStorage.getItem("process-instance-conversation"))
            if(!this.messages)
                this.messages = []

            this.generator.previousMessages = [...this.generator.previousMessages, ...this.messages]

            console.log(this.generator.previousMessages)
        },
        async doit(message) {
            this.loading = true;

            if (message.command.method === 'GET') {
                var path = message.command.path;
                this.$router.push(`${path}`);
                this.loading = false;

            } else {
                await this.submit(message).then((res) => {
                    if (res.data) {
                        this.formatMarkdown(JSON.stringify(res.data));
                    } else {
                        this.formatMarkdown(JSON.stringify(res));
                    }
                }).catch(error => {
                    if (error.response) {
                        this.onError(error);
                    } else {
                        this.loading = false;
                        var message = {
                            role: 'system',
                            text: error
                        }
                        this.messages.push(message);
                    }
                })
            }
        },

        async submit(message) {
            var path = message.command.path;
            if (path.charAt(0) === '/') {
                path = path.substr(1);
            }
            var value = message.command.args;
            var repository = new BaseRepository(axios, path);

            if (message.command.method === 'POST') {
                return await repository.save(value, true);
            } else if (message.command.method === 'PUT') {
                return await repository.save(value, false);
            } else if (message.command.method === 'DELETE') {
                return await repository.delete(value);
            }
        },

        async formatMarkdown(value) {
            this.generator.previousMessages = [{
                role: 'system',
                content: `
You should only respond in JSON format as described below

RESPONSE FORMAT:
[{
    "markdown": "generated markdown text"
}]
                `
            }];
            this.newMessage = `
Generate the following values in markdown text format:
${value}
`;

            await this.generator.generate();

            this.newMessage = "";
        },

    }
}
</script>

<style scoped>
/* .chat-open-btn {
    position: fixed;
    z-index: 999;
    bottom: 15px;
    right: 15px;
} */

/* .chatgpt-icon {
    width: 30px;
    height: 30px;
} */

.chat-open-box {
    position: fixed;
    z-index: 999;
    top: 80px;
    bottom: 20px;
    width: 1211px;
    height: 650px;
}

.user-message {
    background: #9155FD;
    color: #ffffff;
    font-weight: bold;
    padding: 12px;
    border-radius: 20px;
    max-width: 90%;
}

.system-message {
    background: #eeeeee;
    font-weight: bold;
    padding: 12px;
    border-radius: 20px;
    max-width: 90%;
}

.system-message > div {
    max-width: 180px;
}

.message-box {
    overflow-y: auto;
    max-height: 80%;
}

.chat-box {
    position: absolute;
    bottom: 0px;
    right: 0px;
    width: 100%;
}

</style>