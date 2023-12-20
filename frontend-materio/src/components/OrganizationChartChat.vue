<template>
    <div>
        <organization-chart 
                v-if="organizationChart.length > 0"
                :nodes="organizationChart" 
                :key="organizationChart.length"
        ></organization-chart>

        <chat :messages="messages"
                @sendMessage="beforeSendMessage"
        >
            <v-alert type="info"
                    color="deep-purple-accent-4"
                    title="조직도 관리"
                    text="대화형으로 조직도를 관리하십시오.
                    팀(부서) 롤(역할), 직원들을 등록 수정 삭제할 수 있습니다. 예를 들어, 'OOO님을 신입사원으로 관리팀에 등록해줘. 이메일 주소는 new@company.com 이야. 역할은 개발자로 들어오셨어.'와 같은 명령을 할 수 있습니다."
            ></v-alert>
        </chat>
    </div>
</template>

<script>
import partialParse from "partial-json-parser";
import { VectorStorage } from "vector-storage";
import OrgChart from '@balkangraph/orgchart.js';

import ChatGenerator from "./ai/OrganizationChartGenerator";
import OrganizationChart from "./ui/OrganizationChart.vue"

import ChatModule from "./ChatModule.vue";
import Chat from "./Chat.vue";

export default {
    mixins: [ChatModule],
    components: {
        OrganizationChart,
        Chat
    },
    data: () => ({
        path: "organization",
        organizationChart: [],
    }),
    async created() {
        this.init();

        this.generator = new ChatGenerator(this, {
            isStream: true,
            preferredLanguage: "Korean"
        });
        
        this.loadMessages();
        this.loadData(this.path);
    },
    methods: {
        async loadData(path) {
            const value = await this.getData(path);

            if (value) {
                this.organizationChart = JSON.parse(value.organizationChart);
                if (!this.organizationChart) {
                    this.organizationChart = []
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
            let obj = partialParse(textData);

            if(obj && obj.organizationChart) {
                this.organizationChart = obj.organizationChart;

                this.organizationChart.forEach(node => node.img=`https://randomuser.me/api/portraits/women/${Math.round(Math.random() * 90)}.jpg`);

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
    max-height: 60vh;
}

.chat-box {
    position: absolute;
    bottom: 0px;
    right: 0px;
    width: 100%;
}

</style>