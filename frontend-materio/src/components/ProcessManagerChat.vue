<template>
    <div>
        <process-definition
                v-if="bpmn"
                :bpmn="bpmn"
                :processDefinition="processDefinition"
        ></process-definition>
        
        <v-card class="chat-open-box"
                :style="bpmn ? 'min-height: 55vh;' : ''"
        >
            <v-card-text class="message-box"
                    :style="bpmn ? 'height: 45vh;' : ''"
            >
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
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage"

import ChatGenerator from "./ai/ProcessDefinitionGenerator.js";
import ProcessDefinition from './ProcessDefinition.vue';

import StorageBase from "./storage/CommonStorageBase";

export default {
    name: 'ProcessManagerChat',
    components: {
        ProcessDefinition
    },
    data: () => ({
        messages: [],
        newMessage: "",
        generator: null,
        processDefinition: null,
        bpmn: null,
        storage: null,
    }),
    created() {
        this.storage = new StorageBase(this);

        this.generator = new ChatGenerator(this, {
            isStream: true,
            preferredLanguage: "Korean"
        });
        this.init();
    },
    methods:{
        init() {
            this.loadMessages();

            if (this.$route.params && this.$route.params.id) {
                const chatItem = this.messages.find(chat => 
                    chat.role == "system" && chat.content.includes(this.$route.params.id)
                )
                this.bpmn = chatItem.bpmn;
            }
        },

        sendMessage() {
            if (this.newMessage !== "") {
                if(this.newMessage.includes("\n")) {
                    this.newMessage = this.newMessage.replace(/\n/g, "<br/>");
                }
                
                this.init();
                
                this.messages.push({
                    role: "user",
                    content: this.newMessage
                });

                this.generator.generate();
    
                this.messages.push({
                    role:'system',
                    content: '...',
                    isLoading: true,
                });

                this.newMessage = "";
            }
        },

        onModelCreated(response) {
            let messageWriting = this.messages[this.messages.length -1];
            messageWriting.content = response;

            if (response.includes("\n")) {
                messageWriting.content = response.replace(/\n/g, "<br/>");
            }

            let jsonProcess = this.extractProcessJson(response);

            if (jsonProcess) {

                console.log(jsonProcess);

                this.processDefinition = partialParse(jsonProcess);

                messageWriting.bpmn = this.createBpmnXml(this.processDefinition);
                
                this.bpmn = messageWriting.bpmn;

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


            // 콜라보레이션 및 참가자 요소 생성
            const collaboration = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:collaboration');
            collaboration.setAttribute('id', 'Collaboration_1');
            const participant = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:participant');
            participant.setAttribute('id', 'Participant_' + jsonProcess.processDefinitionId);
            participant.setAttribute('name', jsonProcess.processDefinitionName);
            participant.setAttribute('processRef', 'Process_' + jsonProcess.processDefinitionId);
            collaboration.appendChild(participant);
            bpmn.appendChild(collaboration);

            // Process 요소 생성
            const process = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:process');
            process.setAttribute('id', jsonProcess.processDefinitionId)  //.replace(/\s+/g, '_'));
            process.setAttribute('isExecutable', 'true');

            bpmn.appendChild(process);

            // 레인셋 생성
            const laneSet = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:laneSet');
            laneSet.setAttribute('id', 'LaneSet_' + jsonProcess.processDefinitionId);
            process.appendChild(laneSet);

            // 레인 생성 및 역할 할당
            if(jsonProcess.roles)
            jsonProcess.roles.forEach(role => {
                const lane = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:lane');
                lane.setAttribute('id', 'Lane_' + role.name.replace(/\s+/g, '_'));
                lane.setAttribute('name', role.name);
                laneSet.appendChild(lane);

                // 해당 역할에 매핑된 활동들을 레인에 할당
                jsonProcess.activities.forEach(activity => {
                    if (activity.role === role.name) {
                        const flowNodeRef = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:flowNodeRef');
                        flowNodeRef.textContent = activity.id;
                        lane.appendChild(flowNodeRef);
                    }
                });
            });
            
            // 각 활동 (Activity) 요소 생성
            if(jsonProcess.activities)
            jsonProcess.activities.forEach(activity => {
                const task = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:userTask');
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

//            bpmn.appendChild(process);

            // BPMNDiagram 요소 추가
            const bpmnDiagram = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNDiagram');
            bpmnDiagram.setAttribute('id', 'BPMNDiagram_' + jsonProcess.processDefinitionId);
            const bpmnPlane = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNPlane');
            bpmnPlane.setAttribute('id', 'BPMNPlane_' + jsonProcess.processDefinitionId);
            bpmnPlane.setAttribute('bpmnElement', collaboration.getAttribute('id'));
            bpmnDiagram.appendChild(bpmnPlane);

            // 레인의 시각적 표현 추가
            if(jsonProcess.roles)
            jsonProcess.roles.forEach((role, index) => {
                const laneShape = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNShape');
                laneShape.setAttribute('id', 'BPMNShape_Lane_' + role.name.replace(/\s+/g, '_'));
                laneShape.setAttribute('bpmnElement', 'Lane_' + role.name.replace(/\s+/g, '_'));

                const laneBounds = xmlDoc.createElementNS('http://www.omg.org/spec/DD/20100524/DC', 'dc:Bounds');
                laneBounds.setAttribute('x', 100);
                laneBounds.setAttribute('y', 100 + index * 100);
                laneBounds.setAttribute('width', 600);
                laneBounds.setAttribute('height', 100);

                laneShape.appendChild(laneBounds);
                bpmnPlane.appendChild(laneShape);
            });

            // 활동 및 시퀀스 플로우의 시각적 표현 추가
            if(jsonProcess.activities)
            jsonProcess.activities.forEach((activity, index) => {
                const shape = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNShape');
                shape.setAttribute('id', 'BPMNShape_' + activity.id);
                shape.setAttribute('bpmnElement', activity.id);

                const bounds = xmlDoc.createElementNS('http://www.omg.org/spec/DD/20100524/DC', 'dc:Bounds');
                bounds.setAttribute('x', 150 + index * 100); // 위치 예제
                bounds.setAttribute('y', 120 + index * 60); // 위치 예제
                bounds.setAttribute('width', 80);
                bounds.setAttribute('height', 60);

                shape.appendChild(bounds);
                bpmnPlane.appendChild(shape);
            });

            if(jsonProcess.sequences)
            jsonProcess.sequences.forEach(sequence => {
                const edge = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNEdge');
                edge.setAttribute('id', 'BPMNEdge_' + sequence.source + '_' + sequence.target);
                edge.setAttribute('bpmnElement', 'SequenceFlow_' + sequence.source + '_' + sequence.target);

                // Waypoint 예제 (실제 좌표는 활동의 위치에 따라 조정되어야 함)
                const waypoint1 = xmlDoc.createElementNS('http://www.omg.org/spec/DD/20100524/DI', 'di:waypoint');
                waypoint1.setAttribute('x', 200); // 예제 좌표
                waypoint1.setAttribute('y', 150); // 예제 좌표
                edge.appendChild(waypoint1);

                const waypoint2 = xmlDoc.createElementNS('http://www.omg.org/spec/DD/20100524/DI', 'di:waypoint');
                waypoint2.setAttribute('x', 300); // 예제 좌표
                waypoint2.setAttribute('y', 150); // 예제 좌표
                edge.appendChild(waypoint2);

                bpmnPlane.appendChild(edge);
            });

            // // 시각적 요소 생성 (BPMNShape 및 BPMNEdge)
            // if(jsonProcess.activities)
            // jsonProcess.activities.forEach((activity, index) => {
            //     const shape = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNShape');
            //     shape.setAttribute('id', 'BPMNShape_' + activity.id);
            //     shape.setAttribute('bpmnElement', activity.id);

            //     const bounds = xmlDoc.createElementNS('http://www.omg.org/spec/DD/20100524/DC', 'dc:Bounds');
            //     bounds.setAttribute('x', 100 + (index * 150)); // 예제 위치
            //     bounds.setAttribute('y', 100);
            //     bounds.setAttribute('width', 100);
            //     bounds.setAttribute('height', 80);

            //     shape.appendChild(bounds);
            //     bpmnPlane.appendChild(shape);
            // });

            // // 시퀀스 플로우 시각적 요소
            // if(jsonProcess.sequences)
            // jsonProcess.sequences.forEach(sequence => {
            //     const edge = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/DI', 'bpmndi:BPMNEdge');
            //     edge.setAttribute('id', 'BPMNEdge_' + sequence.source + '_' + sequence.target);
            //     edge.setAttribute('bpmnElement', 'SequenceFlow_' + sequence.source + '_' + sequence.target);

            //     // 예제 waypoint
            //     const waypoint1 = xmlDoc.createElementNS('http://www.omg.org/spec/DD/20100524/DI', 'di:waypoint');
            //     waypoint1.setAttribute('x', 150);
            //     waypoint1.setAttribute('y', 140);

            //     const waypoint2 = xmlDoc.createElementNS('http://www.omg.org/spec/DD/20100524/DI', 'di:waypoint');
            //     waypoint2.setAttribute('x', 250);
            //     waypoint2.setAttribute('y', 140);

            //     edge.appendChild(waypoint1);
            //     edge.appendChild(waypoint2);

            //     bpmnPlane.appendChild(edge);
            // });

            bpmn.appendChild(bpmnDiagram);

            // XML 문자열로 변환
            const serializer = new XMLSerializer();
            const xmlString = serializer.serializeToString(xmlDoc);
            return xmlString;
        },

        extractProcessJson(text) {            
            let textAndJson = text.split("--- json ---")
            if(textAndJson && textAndJson.length==2) return textAndJson[1]
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

        async saveDefinition(definition){
            var me = this;
            var putObj = {
                lastModifiedTimeStamp: Date.now(),
                lastModifiedUser: me.storage.userInfo.uid,
                lastModifiedEmail: me.storage.userInfo.email,
                definitionName: definition.processDefinitionName
            }
            
            await me.storage.putObject(`db://definitions/${definition.processDefinitionId}/information`, putObj);

            // Create an instance of VectorStorage
            const vectorStore = new VectorStorage({ openAIApiKey: this.generator.getToken() });

            // Add a text document to the store
            await vectorStore.addText(JSON.stringify(definition), {
                category: definition.processDefinitionId
            });

        },

        onGenerationFinished(responses){
            // console.log(responses);
            let messageWriting = this.messages[this.messages.length -1];
            delete messageWriting.isLoading;

            if(this.processDefinition){
                this.saveDefinition(this.processDefinition);
            }

            this.saveMessages();
        },

        async saveMessages() {
            // window.localStorage.setItem("process-definition-conversation", JSON.stringify(this.messages));
        },

        loadMessages() {
            this.messages = JSON.parse(window.localStorage.getItem("process-definition-conversation"));
            if (!this.messages) {
                this.messages = [];
            }
            this.generator.previousMessages = [...this.generator.previousMessages, ...this.messages];

            // console.log(this.generator.previousMessages);
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
                    text: error.message
                };

                this.messages.push(message);
            }
        },

    }
}
</script>

<style scoped>
.bpmn-area {
    min-height: 34vh;
}

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