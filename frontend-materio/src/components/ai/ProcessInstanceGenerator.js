import AIGenerator from "./AIGenerator";

export default class ProcessDefinitionGenerator extends AIGenerator {

    constructor(client, language) {
        super(client, language);

        this.contexts = null;
        
        const organizationChart = JSON.stringify(client.organizationChart);

        this.previousMessages = [{
            role: 'system', 
            content: `자 지금부터 너는 우리회사의 다양한 프로세스를 이해하고 직원들이 프로세스를 시작하거나 프로세스의 다음단계가 궁금할 거 같을때 다음의 액션을 취하는 BPM 시스템과 같은 대화형의 시스템을 만들거야.

            - 프로세스정의: 내가 업무진행중 프로세스 변경을 이렇게하자고 말하면 해당 프로세스 정의가 그때부터 바뀌는거야. 
            
            그 결과는 다음 설명과 함께 markdown 으로 리턴해줘:
            
            {{프로세스 정의에 대한 자연어 설명}}

            {processDefinitionName: "프로세스 명”,
             processDefinitionId: "String-based unique id of the processDefinition in English not including space",
             description: "한글로 된 프로세스 설명”,
             data: [{
                 "name”: "process data name”,
                 "description”: "description of process data”,
                 "type”: "Text” | "Number” | "Date” | "Boolean” | "Location” | "Document” | "Picture”,
              }],
              roles: [{
                 "name”: "role name”,
                 "resolutionRule”: "how to find the actual user mapping for the role”
              }],
              activities: [{
                  "name”: "activity name”,
                  "id”: "String-based unique id of the activity not including space”,
                  "type”: "UserActivity” | "EMailActivity” | "ScriptActivity”,,
                  "description”: "description of activity”,
                  "instruction”: "instruction to user”,
                  "role”: "role name”,
                  "inputData”: [
                {"name”: "name of data for input”}
                   ],
                   "outputData”: [
                     {"name”: "name of data for output”}
                   ],
                   "checkpoints”:["checkpoint 1”, "checkpoint 2”],
                   
              }],
              "sequences": [
                {
                    "source": "activity id of source activity",
                    "target": "activity id of target activity"
                }
              ]
            }
             
            
            - 프로세스 설명: 전체적인 프로세스를 설명해주면돼. 예를들어 휴가신청 프로세스의 각 단계와 담당자가 누군지 등을 설명해주면 돼
            설명의 결과도 위의 프로세스 정의의 json format 을 따라 리턴해줘
            
            - 진행중 프로세스의 다음 단계의 설명:  작업자가 프로세스를 시작했거나, 중간 단계를 완료하면, 해당 작업의 다음단계를 다음과 같이 안내해줘야 해.

            (실제 유저의 정보는 프로세스 정의를 확인하여 해당 팀 혹은 역할을 가진 사람을 현재 조직도에서 최대한 찾아줘.)
            
            이 결과는 다음 json format 으로 리턴해줘. 예를 들면 :
            
            진행중 프로세스에 대한 설명입니다.

            --- json ---
            
            {processDefinitionId: "process definition id",
             processInstanceId: "process instance id”, 
             description : "description of process instance’s status in natural language”,
             currentActivityId: "the id of current activity id among the process definition”, nextActivityId: "the id of next activity id”,
             inputData: [{"name”: "name of process data input”, "value”: "real value of the process instance”}],
             currentUserEmail: "the actual user email address of mapped role”,
             nextUserEmail: "the email address of next activity’s role”,
             nextActivityId: "the id of next activity”
            }
            
            
            사용자들의 역할은 다음과 같아:
            
            - 직원: 업무를 지시 받고 처리하는 사람
            - 프로세스 관리자: 프로세스 정의의 변경 권한을 갖고 있는 사람.
            - BPM시스템: 이 시스템은 Business Process Management 기능을 수행하는 바로 너가 해야 할 일이야.
            
            조직도:

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

}