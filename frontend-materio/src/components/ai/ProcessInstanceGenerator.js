import AIGenerator from "./AIGenerator";

export default class ProcessDefinitionGenerator extends AIGenerator {

    constructor(client, language) {
        super(client, language);

        this.contexts = null;
        this.model = "gpt-4"
        
        const organizationChart = JSON.stringify(client.organizationChart);

        this.previousMessages = [{
            role: 'system', 
            content: `자 지금부터 너는 우리 회사의 다양한 프로세스를 이해하고 직원들이 프로세스를 시작하거나 프로세스의 다음 단계가 궁금할 거 같을 때 다음의 액션을 취하는 BPM 시스템과 같은 대화형의 시스템을 만들거야.

            
            - 진행중 프로세스의 다음 단계의 설명:  작업자가 프로세스를 시작했거나, 중간 단계를 완료하면, 해당 작업의 다음단계를 다음과 같이 안내해줘야 해.

            (실제 유저의 정보는 프로세스 정의를 확인하여 해당 팀 혹은 역할을 가진 사람을 현재 조직도에서 최대한 찾아줘.)
            
            이 결과는 다음과 같이 json format 과 함께 리턴해줘.

            그 결과는 다음 설명과 함께 markdown (three backticks) 으로 리턴해줘:
            
            \`\`\`
            {processDefinitionId: "process definition id",
             processInstanceId:  "${this.uuid()}", 
             description : "description of process instance’s status in natural language”,
             currentActivityId: "the id of current activity id among the process definition”,
             nextActivityId: "the id of next activity id”,
             inputData: [{"name”: "name of process data input”, "value”: "real value of the process instance”}],
             currentUserEmail: "the actual user email address of mapped role”,
             nextUserEmail: "the email address of next activity’s role”
            }
            \`\`\`
                        
            
            조직도 정보:

            ${organizationChart}


            프로세스 정의:
            
`
        }];
    }

    setContexts(contexts) {
        this.contexts = contexts;

        contexts.forEach(context => {
            this.previousMessages[0].content += context + "\n\n";
        });
    }

    createPrompt() {
        return this.client.newMessage;
    }

    uuid() {
        function s4() {
            return Math.floor((1 + Math.random()) * 0x10000)
                .toString(16)
                .substring(1);
        }

        return s4() + s4() + '-' + s4() + '-' + s4() + '-' +
            s4() + '-' + s4() + s4() + s4();
    }

}