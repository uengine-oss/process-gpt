<template>
    <div>
        <process-definition
                :bpmn="bpmn"
                :processDefinition="processDefinition"
                :key="bpmn.length"
        ></process-definition>

        <chat-button
                :chatDialog="chatDialog"
                :messages="messages"
                :alertInfo="alertInfo"
                :disableChat="disableChat"
                @toggleChatDialog="toggleChatDialog"
                @beforeSendMessage="beforeSendMessage"
                @sendEditedMessage="sendEditedMessage"
        ></chat-button>

        <v-btn v-if="testEnabled" @click="runTest">test</v-btn> 
    </div>
</template>

<script>
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage";

import ChatGenerator from "../ai/ProcessDefinitionGenerator";
import ProcessDefinition from '../ProcessDefinition.vue';
import ChatButton from "../ui/ChatButton.vue";

import ChatModule from "../ChatModule.vue";
import jp from "jsonpath"

export default {
    mixins: [ChatModule],
    name: 'ProcessManagerChat',
    components: {
        ProcessDefinition,
        ChatButton,
    },
    data: () => ({
        processDefinition: null,
        bpmn: "",
        path: "definitions",
        alertInfo: {
            title: "프로세스 정의 관리",
            text: "대화형으로 프로세스를 관리하십시오. 예를 들어, '영업관리 프로세스를 다음과 같이 등록해줘: 1. 영업기회등 고객명, 예상사업규모, 키맨, 요구사항 2. 제안 작성: 제안 내용, 가격 3. 수주 혹은 실주 4. 수주한 경우, 계약진행' 와 같은 명령을 할 수 있습니다.",
        },
    }),
    async created() {
        this.init();

        this.generator = new ChatGenerator(this, {
            isStream: true,
            preferredLanguage: "Korean"
        });
    },
    watch: {
        "$route": {
            deep: true,
            async handler(newVal, oldVal) {
                if (newVal.path !== oldVal.path) {
                    this.processDefinition = null;
                    this.bpmn = "";
                    this.chatDialog = false;
                    await this.init();
                }
            }
        },
    },
    methods: {


        jsonPathReplace(src, jsonPath, newData) {
            // JSONPath를 사용하여 경로의 노드들을 찾음
            const nodes = jp.nodes(src, jsonPath);

            // 각 노드의 경로를 사용하여 src에서 해당 위치를 찾아 newData로 교체
            nodes.forEach((node) => {
                let currentObj = src;
                // 마지막 프로퍼티 전까지 객체를 탐색
                for (let i = 1; i < node.path.length - 1; i++) {
                    currentObj = currentObj[node.path[i]];
                }

                // 마지막 프로퍼티를 newData로 변경
                currentObj[node.path[node.path.length - 1]] = newData;
            });

            return src;
        },

        jsonPathAdd(src, jsonPath, newData) {
            // JSONPath를 사용하여 경로의 노드들을 찾음
            const nodes = jp.nodes(src, jsonPath);

            // 각 노드의 경로를 사용하여 src에서 해당 위치를 찾아 newData를 추가
            nodes.forEach((node) => {
                let currentObj = src;
                // 마지막 프로퍼티 전까지 객체를 탐색
                for (let i = 1; i < node.path.length; i++) {
                    currentObj = currentObj[node.path[i]];
                }

                // Array 타입인 경우, newData를 배열에 추가
                if (Array.isArray(currentObj)) {
                    currentObj.push(newData);
                } else {
                    // Object 타입인 경우, 오류 처리 또는 다른 방법으로 추가
                    console.error('Target is not an array. Cannot add new data.');
                }
            });

            return src;
        },

        jsonPathDelete(src, jsonPath) {
            // JSONPath를 사용하여 경로의 노드들을 찾음
            const nodes = jp.nodes(src, jsonPath);

            // 각 노드의 경로를 사용하여 src에서 해당 위치를 찾아 제거
            nodes.forEach((node) => {
                let currentObj = src;
                // 마지막 프로퍼티 전까지 객체를 탐색
                for (let i = 1; i < node.path.length - 1; i++) {
                    currentObj = currentObj[node.path[i]];
                }

                // 마지막 프로퍼티가 배열의 요소를 가리키는 경우 splice로 제거
                const propertyIndex = node.path[node.path.length - 1];
                if (Array.isArray(currentObj) && Number.isInteger(propertyIndex)) {
                    currentObj.splice(propertyIndex, 1);
                } else {
                    console.error('Target is not an array element. Cannot remove.');
                }
            });

            return src;
        },

        async loadData(path) {
            const value = await this.getData(path);

            if (value) {
                if (this.$route.params && this.$route.params.id) {
                    this.processDefinition = JSON.parse(value.model);
                    this.bpmn = this.createBpmnXml(this.processDefinition);
                    this.saveDefinition(this.processDefinition);

                    if (!this.processDefinition) {
                        this.processDefinition = null;
                    }
                }
                // } else {
                //     this.messages = [];

                //     var list = Object.values(value);
                //     list.forEach(item => {
                //         const msg = JSON.parse(item.messages);
                //         this.messages = [...this.messages, ...msg];

                //         item.model = JSON.parse(item.model);
                //         this.saveDefinition(item.model);
                //     });

                //     this.generator.previousMessages = [
                //         ...this.generator.previousMessages, 
                //         ...this.messages
                //     ];
                // }
            }
        },

        beforeSendMessage(newMessage) {
            this.sendMessage(newMessage);
        },

        afterModelCreated(response) {
            try {
                let jsonProcess = this.extractJSON(response);

                if (jsonProcess) {
                    let unknown = partialParse(jsonProcess);
                    if(unknown.modifications){ //means process modification
                        
                        unknown.modifications.forEach(modification=>{
                            if(modification.action=="replace"){
                                this.jsonPathReplace(this.processDefinition, modification.targetJsonPath, modification.value)
                                this.bpmn = this.createBpmnXml(this.processDefinition)    
                            }else if(modification.action=="add"){
                                this.jsonPathAdd(this.processDefinition, modification.targetJsonPath, modification.value)
                                this.bpmn = this.createBpmnXml(this.processDefinition)    
                            }else if(modification.action=="delete"){
                                this.jsonPathDelete(this.processDefinition, modification.targetJsonPath)
                                this.bpmn = this.createBpmnXml(this.processDefinition)    
                            }

                        })

                    }else if(unknown.processDefinitionId){
                        this.processDefinition = unknown;
                        this.bpmn = this.createBpmnXml(this.processDefinition)
                    }
                }
                
            } catch (error) {
                console.log(error)
            }
        },

        afterGenerationFinished() {
            let path = "";
            let modelText = "";
            let putObj =  {
                messages: this.messages,
                model: "",
            };
            
            if (this.processDefinition) {
                path = `${this.path}/${this.processDefinition.processDefinitionId}`;

                modelText = JSON.stringify(this.processDefinition);
                this.saveDefinition(this.processDefinition);

                putObj.model = modelText;
                this.putObject(path, putObj);
            }
        },

        async saveDefinition(definition) {
            // Create an instance of VectorStorage
            const apiToken = this.generator.getToken();
            const vectorStore = new VectorStorage({ openAIApiKey: apiToken });

            // Add a text document to the store
            await vectorStore.addText(JSON.stringify(definition), {
                category: definition.processDefinitionId
            });
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
                    if (activity && activity.role === role.name) {
                        const flowNodeRef = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:flowNodeRef');
                        flowNodeRef.textContent = activity.id;
                        lane.appendChild(flowNodeRef);
                    }
                });
            });
            
            // 각 활동 (Activity) 요소 생성
            if(jsonProcess.activities)
            jsonProcess.activities.forEach(activity => {
                if(activity){
                    const task = xmlDoc.createElementNS('http://www.omg.org/spec/BPMN/20100524/MODEL', 'bpmn:userTask');
                    task.setAttribute('id', activity.id);
                    task.setAttribute('name', activity.name);
                    process.appendChild(task);
                }
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
                if(!activity) return

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
                if(!sequence) return
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

        createTests(){

            return {
                testJsonPathReplace(me){ 
                    // 사용 예시
                    let src = {
                        processDefId: "vacation_request",
                        activities: [{
                            activityId: "request_vacation",
                            outputData: []
                        }]
                    };

                    // 새로운 객체로 교체할 내용
                    const newActivity = {
                        activityId: "request_vacation",
                        outputData: ["new data"],
                        additionalField: "example"
                    };

                    // 함수 호출
                    src = me.jsonPathReplace(src, "$.activities[?(@.activityId=='request_vacation')]", newActivity);

                    console.log(src);
                }
            }

        }
    }
}
</script>

<style scoped>

</style>