<template>
    <div>

        <vue-bpmn v-if="bpmn" :key="bpmn.length"
                    :bpmn="bpmn"
                    :options="options"
                    v-on:error="handleError"
                    v-on:shown="handleShown"
                    v-on:loading="handleLoading"
            ></vue-bpmn>

        <v-card class="chat-open-box">



            <v-card-text class="message-box" ref="messages">



                <div v-for="(message, index) in messages"
                        :key="index"
                >
                    <div v-if="message.role == 'user'"
                            class="d-flex justify-end my-2"
                    >
                        <div class="user-message">

                            

                            {{ message.text }} 
                        </div>
                        <div class="ml-1">
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
                        <div class="d-flex system-message">
                            <div v-html="message.text"></div>
                        </div>
                        <br>
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
                            System
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
import ChatGenerator from "./ai/ProcessDefinitionGenerator.js";

import BaseRepository from "./repository/BaseRepository";
import axios from "@axios";
import VueBpmn from './Bpmn.vue';
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage"

export default {
    name: 'ProcessManagerChat',
    components: {
        VueBpmn
    },
    data: () => ({
        messages: [],
        newMessage: "",
        generator: null,
        loading: false,
        openChatBox: false,
        processDefinition: null,
        // bpmn: `
        // <?xml version="1.0" encoding="UTF-8"?><bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" xmlns:di="http://www.omg.org/spec/DD/20100524/DI" id="Definitions_1" targetNamespace="http://bpmn.io/schema/bpmn" exporter="Custom BPMN Modeler" exporterVersion="1.0"><bpmn:process id="VacationRequestProcess" isExecutable="true"><bpmn:task id="VacationRequest" name="휴가 신청"/><bpmn:task id="VacationApproval" name="휴가 승인"/><bpmn:task id="VacationCheck" name="휴가 승인 확인 및 잔여일수 체크"/><bpmn:sequenceFlow id="SequenceFlow_VacationRequest_VacationApproval" sourceRef="VacationRequest" targetRef="VacationApproval"/><bpmn:sequenceFlow id="SequenceFlow_VacationApproval_VacationCheck" sourceRef="VacationApproval" targetRef="VacationCheck"/></bpmn:process><bpmndi:BPMNDiagram id="BPMNDiagram_1"><bpmndi:BPMNPlane id="BPMNPlane_1" bpmnElement="VacationRequestProcess"><bpmndi:BPMNShape id="BPMNShape_VacationRequest" bpmnElement="VacationRequest"><dc:Bounds xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" x="100" y="100" width="100" height="80"/></bpmndi:BPMNShape><bpmndi:BPMNShape id="BPMNShape_VacationApproval" bpmnElement="VacationApproval"><dc:Bounds xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" x="250" y="100" width="100" height="80"/></bpmndi:BPMNShape><bpmndi:BPMNShape id="BPMNShape_VacationCheck" bpmnElement="VacationCheck"><dc:Bounds xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" x="400" y="100" width="100" height="80"/></bpmndi:BPMNShape><bpmndi:BPMNEdge id="BPMNEdge_VacationRequest_VacationApproval" bpmnElement="SequenceFlow_VacationRequest_VacationApproval"><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="150" y="140"/><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="250" y="140"/></bpmndi:BPMNEdge><bpmndi:BPMNEdge id="BPMNEdge_VacationApproval_VacationCheck" bpmnElement="SequenceFlow_VacationApproval_VacationCheck"><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="150" y="140"/><di:waypoint xmlns:di="http://www.omg.org/spec/DD/20100524/DI" x="250" y="140"/></bpmndi:BPMNEdge></bpmndi:BPMNPlane></bpmndi:BPMNDiagram></bpmn:definitions>
        // `

        bpmn: null
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
            
        },

        sendMessage() {
            if (this.newMessage !== "") {
                this.loading = true;
                this.init();
                
                this.messages.push(
                    {
                        role: "user",
                        text: this.newMessage
                    }
                );

                this.generator.generate();
    

                this.messages.push({
                    role:'system',
                    text: '.'
                });

                this.newMessage = "";
            }
        },

        onModelCreated(response){

            let messageWriting = this.messages[this.messages.length -1]
            messageWriting.text = response

            let jsonProcess = this.extractProcessJson(response)

            if (jsonProcess) {

                console.log(jsonProcess)

                this.processDefinition = partialParse(jsonProcess)

                messageWriting.bpmn = this.createBpmnXml(this.processDefinition)
                this.bpmn = messageWriting.bpmn
            
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
            // Create an instance of VectorStorage
            const vectorStore = new VectorStorage({ openAIApiKey: this.generator.getToken() });

            // Add a text document to the store
            await vectorStore.addText(JSON.stringify(definition), {
                category: definition.processDefinitionId
            });

        },

        onGenerationFinished(responses){
            console.log(responses);


            this.loading = false;
            if(this.processDefinition){
                this.saveDefinition(this.processDefinition)
            }

            // responses.forEach(response=> {
            //     console.log(response);

            //     if (response.error) {
            //         message = {
            //             role:'system',
            //             text: response.error.speak ? response.error.speak : response.error
            //         };

            //         this.messages.push(message);

            //     }
            //     else if (response.command) {
            //         if (response.thoughts) {
            //             // if (response.thoughts.plan && response.thoughts.plan.length > 0) {
            //             //     response.thoughts.plan.forEach((planMsg, index) => {
            //             //         message = {
            //             //             role:'system',
            //             //             text: planMsg
            //             //         };

            //             //         if (index == response.thoughts.plan.length-1) {
            //             //             message.command = response.command
            //             //         }

            //             //         this.messages.push(message);
            //             //     })
            //             // }

            //             if (response.thoughts.criticism) {
            //                 message = {
            //                     role:'system',
            //                     text: response.thoughts.criticism,
            //                 };

            //                 this.messages.push(message);
            //             }

            //             if (response.thoughts.speak) {
            //                 message = {
            //                     role:'system',
            //                     text: response.thoughts.speak,
            //                     command: response.command
            //                 };

            //                 this.messages.push(message);

            //             }
            //         }

            //         if (!message && response.command) {
            //             message = {
            //                 role:'system',
            //                 text: response.command.name + "을 다음의 아규먼트로 실행합니다: "
            //                     + JSON.stringify(response.command.args),
            //                 command: response.command
            //             };

            //             this.messages.push(message);
            //         }
            //     }
            //     else if (response.markdown) {
            //         message = {
            //             role:'system',
            //             text: response.markdown.replace(/(?:\r\n|\r|\n)/g, '<br />')
            //         };

            //         this.messages.push(message);

            //     }
            // });
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
                    text: error.message
                };

                this.messages.push(message);
            }
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
    top: 270px;
    bottom: 20px;
    width: 1211px;
    height: 500px;
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