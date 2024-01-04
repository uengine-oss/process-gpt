<template>
    <div>
        <organization-chart 
                :nodes="organizationChart" 
                :key="organizationChart.length"
        ></organization-chart>

        <chat-button
                :chatDialog="chatDialog"
                :messages="messages"
                :alertInfo="alertInfo"
                @toggleChatDialog="toggleChatDialog"
                @beforeSendMessage="beforeSendMessage"
                @editSendMessage="editSendMessage"
        ></chat-button>
    </div>
</template>

<script>
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage";
import OrgChart from '@balkangraph/orgchart.js';

import ChatGenerator from "./ai/OrganizationChartGenerator";
import OrganizationChart from "./ui/OrganizationChart.vue"
import ChatButton from "./ui/ChatButton.vue";

import ChatModule from "./ChatModule.vue";

export default {
    mixins: [ChatModule],
    components: {
        OrganizationChart,
        ChatButton
    },
    data: () => ({
        path: "organization",
        organizationChart: [],
        alertInfo: {
            title: "조직도 관리",
            text: "대화형으로 조직도를 관리하십시오. 팀(부서) 롤(역할), 직원들을 등록 수정 삭제할 수 있습니다. 예를 들어, '개발팀, 관리팀을 등록하고, 홍길동님을 신입사원으로 관리팀에 등록해줘. 이메일 주소는 new@company.com 이야. 역할은 개발자로 들어오셨어. 관리팀의 팀장은 아무개 팀장님이야.' 와 같은 명령을 할 수 있습니다.",
        }
    }),
    async created() {
        await this.init();

        this.generator = new ChatGenerator(this, {
            isStream: true,
            preferredLanguage: "Korean"
        });
        this.loadData(this.path);
    },
    methods: {
        async loadData(path) {
            const value = await this.getData(path);

            if (value) {
                if (value.organizationChart && value.organizationChart.length > 0) {
                    let orgChart = partialParse(value.organizationChart);
                    if (orgChart && orgChart.length > 0) {
                        const isMyOrg = orgChart.some(item =>
                            item.email == this.userInfo.email
                        );
                        if (isMyOrg) {
                            this.organizationChart = orgChart;

                            this.messages = partialParse(value.messages);
                            this.generator.previousMessages = [
                                ...this.generator.previousMessages,
                                ...this.messages
                            ];
                        }
                    }
                    if (!this.organizationChart) {
                        this.organizationChart = []
                    }
                }
            }
        },

        beforeSendMessage(newMessage) {
            this.sendMessage(newMessage);
        },

        afterModelCreated(response) {
            this.drawChart(response);
        },

        drawChart(textData) {
            try {
                let obj = partialParse(textData);

                if(obj && obj.organizationChart) {
                    this.organizationChart = obj.organizationChart;

                    this.organizationChart.forEach(node => node.img=`https://randomuser.me/api/portraits/women/${Math.round(Math.random() * 90)}.jpg`);

                }
            } catch (error) {
                console.log(error);
            }
        },

        afterGenerationFinished(putObj) {
            var chartText = "";
            if (this.organizationChart) {
                chartText = JSON.stringify(this.organizationChart);
            }

            putObj.organizationChart = chartText;

            this.saveMessages(this.path, putObj);
        },
    }
}
</script>

<style scoped>
.chart-area {
    margin-bottom: 12px;
}

</style>