<template>

    <div>

        <organization-chart :nodes="organizationChart" :key="organizationChart.length"/>


        <v-card class="chat-open-box">


            <v-card-text class="message-box" ref="messages">

                <v-alert
    type="info"
    color="deep-purple-accent-4"
    title="조직도 관리"
    text="대화형으로 조직도를 관리하십시오.
     팀(부서) 롤(역할), 직원들을 등록 수정 삭제할 수 있습니다. 예를 들어, 'OOO님을 신입사원으로 관리팀에 등록해줘. 이메일 주소는 new@company.com 이야. 역할은 개발자로 들어오셨어.'와 같은 명령을 할 수 있습니다."
  ></v-alert>

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
                            <div v-html="message.content"></div>
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
import ChatGenerator from "./ai/OrganizationChartGenerator.js";
import OrganizationChart from "./ui/OrganizationChart.vue"
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage"
import OrgChart from '@balkangraph/orgchart.js';

export default {
    name: 'OrganizationChartChat',
    components: {
        OrganizationChart
    },
    data: () => ({
        messages: [],
        newMessage: "",
        generator: null,
        loading: false,
        openChatBox: false,
        processDefinition: null,
        bpmn: null,
        organizationChart: [

        //{ "id": "개발팀", "name": "개발팀", "tags": ["group"], "description": "" }, { "id": "jyjang@uengine.org", "stpid": "개발팀", "name": "장진영", "title": "CTO" }, { "id": "BPM팀", "name": "BPM팀", "tags": ["group"], "description": "" }, { "id": "sanghoon@uengine.org", "stpid": "BPM팀", "name": "김상훈" }, { "id": "이수헌", "stpid": "BPM팀", "name": "이수헌" }, { "id": "양성원", "stpid": "BPM팀", "name": "양성원" }, { "id": "오순영", "stpid": "BPM팀", "name": "오순영", "title": "회계담당" }, { "id": "인사팀", "name": "인사팀", "tags": ["group"], "description": "" }, { "id": "서원주", "stpid": "인사팀", "name": "서원주" }, { "id": "강서구", "stpid": "인사팀", "name": "강서구" }, { "id": "교육팀", "name": "교육팀", "tags": ["group"], "description": "" }, { "id": "sjjung@uengine.org", "stpid": "교육팀", "name": "정석진", "title": "팀장" }, { "id": "배동재", "stpid": "교육팀", "name": "배동재" }, { "id": "김근영", "stpid": "교육팀", "name": "김근영", "title": "회계담당" }
         //{ "id": "개발팀", "name": "개발팀", "description": "개발팀" }, { "id": "jyjang@uengine.org", "name": "장진영", "pid": "개발팀", "role": "CTO", "img": "https://randomuser.me/api/portraits/women/6.jpg" }, { "id": "BPM팀", "name": "BPM팀", "description": "BPM팀" }, { "id": "sanghoon@uengine.org", "name": "김상훈", "pid": "BPM팀" }, { "id": "이수헌", "name": "이수헌", "pid": "BPM팀" }, { "id": "양성원", "name": "양성원", "pid": "BPM팀" }, { "id": "오순영", "name": "오순영", "pid": "BPM팀", "role": "회계담당" }, { "id": "인사팀", "name": "인사팀", "description": "인사팀" }, { "id": "서원주", "name": "서원주", "pid": "인사팀" }, { "id": "강서구", "name": "강서구", "pid": "인사팀" }, { "id": "교육팀", "name": "교육팀", "description": "교육팀" }, { "id": "sjjung@uengine.org", "name": "정석진", "pid": "교육팀", "role": "팀장" }, { "id": "배동재", "name": "배동재", "pid": "교육팀" }, { "id": "김근영", "name": "김근영", "pid": "교육팀", "role": "회계담당" } 
        //{ id: "devs", name: "개발팀", description: "Top Management" }, { id: "BPM", pid: "devs", name: "BPM팀", description: "BPM Team" }, { id: "HR", name: "인사팀", description: "Human Resource" }, { id: "education", name: "교육팀", description: "Education Team" }, { id: 1, stpid: "devs", name: "장진영", title: "CTO", email: "jyjang@uengine.org" }, { id: 2, stpid: "BPM", name: "김상훈", email: "sanghoon@uengine.org" }, { id: 3, stpid: "BPM", name: "이수헌"}, { id: 4, stpid: "BPM", name: "양성원"}, { id: 5, stpid: "BPM", name: "오순영", title: "회계담당" }, { id: 6, stpid: "HR", name: "서원주"}, { id: 7, stpid: "HR", name: "강서구"}, { id: 8, stpid: "education", name: "정석진", title: "팀장", email: "sjjung@uengine.org" }, { id: 9, stpid: "education", name: "배동재"}, { id: 10, stpid: "education", name: "김근영", title: "회계담당" } 

                    // { id: 1, name: "Denny Curtis", title: "CEO", img: "https://cdn.balkan.app/shared/2.jpg" },
                    // { id: 2, pid: 1, name: "Ashley Barnett", title: "Sales Manager", img: "https://cdn.balkan.app/shared/3.jpg" },
                    // { id: 3, pid: 1, name: "Caden Ellison", title: "Dev Manager", img: "https://cdn.balkan.app/shared/4.jpg" },
                    // { id: 4, pid: 2, name: "Elliot Patel", title: "Sales", img: "https://cdn.balkan.app/shared/5.jpg" },
                    // { id: 5, pid: 2, name: "Lynn Hussain", title: "Sales", img: "https://cdn.balkan.app/shared/6.jpg" },
                    // { id: 6, pid: 3, name: "Tanner May", title: "Developer", img: "https://cdn.balkan.app/shared/7.jpg" },
                    // { id: 7, pid: 3, name: "Fran Parsons", title: "Developer", img: "https://cdn.balkan.app/shared/8.jpg" }


        ]
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

        sendMessage() {
            if (this.newMessage !== "") {
                this.loading = true;
                this.init();
                
                this.messages.push(
                    {
                        role: "user",
                        content: this.newMessage
                    }
                );

                this.generator.generate();
    

                this.messages.push({
                    role:'system',
                    content: '.'
                });

                this.newMessage = "";

                this.saveMessages()
            }
        },

        onModelCreated(response){

            let messageWriting = this.messages[this.messages.length -1]
            messageWriting.content = response

            this.drawChart(messageWriting.content)

        },

        drawChart(message){
            let obj = partialParse(message)

            if(obj.organizationChart){
                this.organizationChart = obj.organizationChart

                this.organizationChart.forEach(node=>node.img=`https://randomuser.me/api/portraits/women/${Math.round(Math.random() * 90)}.jpg`)

            }
        },

        onGenerationFinished(responses){
            // console.log(responses);
            this.loading = false;
            if(this.processDefinition){
                this.saveDefinition(this.processDefinition)
            }
            this.saveMessages()
        },

        saveMessages(){
            window.localStorage.setItem("organization-chart-conversation", JSON.stringify(this.messages))
            window.localStorage.setItem("organization-chart", JSON.stringify(this.organizationChart))
        },
        loadMessages(){
            this.messages = JSON.parse(window.localStorage.getItem("organization-chart-conversation"))
            if(!this.messages)
                this.messages = []

            this.organizationChart = JSON.parse(window.localStorage.getItem("organization-chart"))
            if(!this.organizationChart)
                this.organizationChart = []

            this.generator.previousMessages = [...this.generator.previousMessages, ...this.messages]

            console.log(this.generator.previousMessages)
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
    bottom: 20px;
    width: 1211px;
    height: 300px;
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