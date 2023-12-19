<template>

    <div>
        <organization-chart 
            :nodes="organizationChart" 
            :key="organizationChart.length"
        ></organization-chart>

        <Chat :messages="messages"
            @sendMessage="beforeSendMessage"
        />
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

        await this.loadMessages();
    },
    methods: {
        loadData() {
            this.organizationChart = JSON.parse(this.value.organizationChart);
            if (!this.organizationChart) {
                this.organizationChart = []
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

            if(obj.organizationChart){
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