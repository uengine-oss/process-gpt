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
                            <div v-html="message.content"></div>
                            <v-progress-circular
                                    v-if="message.isLoading"
                                    indeterminate
                                    color="grey"
                            ></v-progress-circular>
                        </v-sheet>
                        <vue-bpmn v-if="message.bpmn"
                                :key="message.bpmn.length"
                                :bpmn="message.bpmn"
                                :options="options"
                                v-on:error="handleError"
                                v-on:shown="handleShown"
                                v-on:loading="handleLoading"
                        ></vue-bpmn>
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
        bpmn: null
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
            this.loadMessages()
        },

        async sendMessage() {
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

                if(!this.generator.contexts){
                    let contexts = await this.queryFromVectorDB(this.newMessage)
                    this.generator.setContexts(contexts)
                }

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

            let messageWriting = this.messages[this.messages.length -1];
            messageWriting.content = response;

            if (response.includes("\n")) {
                messageWriting.content = response.replace(/\n/g, "<br/>");
            }

            let jsonProcess = this.extractJSON(response);
            if(!jsonProcess) {
                jsonProcess = this.extractCode(response);
            }
            if(response.startsWith("{")) {
                jsonProcess = response;
            }

            if(jsonProcess && jsonProcess.processDefinitionId) {

                jsonProcess = partialParse(jsonProcess);
                messageWriting.content = jsonProcess.description;
                this.processDefinition = jsonProcess;

                messageWriting.bpmn = this.createBpmnXml(jsonProcess);
            
                console.log(messageWriting.bpmn);

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
    max-height: 74vh;
}

.chat-box {
    position: absolute;
    bottom: 0px;
    right: 0px;
    width: 100%;
}

</style>