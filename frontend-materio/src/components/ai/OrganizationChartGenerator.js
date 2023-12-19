import AIGenerator from "./AIGenerator";

/**
     { id: "directors", name: "Directors", tags: ["directors-group", "group"], description: "Top Management" },
    { id: "devs", name: "Dev Team", pid: 4, tags: ["devs-group", "group"], description: "Research and Development" },
    { id: "sales", name: "Sales Team", pid: 9, tags: ["sales-group", "group"], description: "Sales and Marketing" },
    { id: 1, stpid: "directors", name: "Billy Moore", title: "CEO", img: "https://cdn.balkan.app/shared/2.jpg" },
    { id: 2, stpid: "directors", name: "Marley Wilson", title: "Director", img: "https://cdn.balkan.app/shared/anim/1.gif" },
    { id: 3, stpid: "directors", name: "Bennie Shelton", title: "Shareholder", img: "https://cdn.balkan.app/shared/4.jpg" },
    { id: 4, pid: "directors", name: "Billie Rose", title: "Dev Team Lead", img: "https://cdn.balkan.app/shared/5.jpg" },
    { id: "hrs", pid: "directors", name: "HR Team", tags: ["hrs-group", "group"], description: "Human Resource | London" },
    { id: 5, stpid: "hrs", name: "Glenn Bell", title: "HR", img: "https://cdn.balkan.app/shared/10.jpg" },
    { id: 6, stpid: "hrs", name: "Marcel Brooks", title: "HR", img: "https://cdn.balkan.app/shared/11.jpg" },
    { id: 7, stpid: "hrs", name: "Maxwell Bates", title: "HR", img: "https://cdn.balkan.app/shared/12.jpg" },
    { id: 8, stpid: "hrs", name: "Asher Watts", title: "Junior HR", img: "https://cdn.balkan.app/shared/13.jpg" },
    { id: 9, pid: "directors", name: "Skye Terrell", title: "Manager", img: "https://cdn.balkan.app/shared/12.jpg" },
    { id: 10, stpid: "devs", name: "Jordan Harris", title: "JS Developer", img: "https://cdn.balkan.app/shared/6.jpg" },
    { id: 11, stpid: "devs", name: "Will Woods", title: "JS Developer", img: "https://cdn.balkan.app/shared/7.jpg" },
    { id: 12, stpid: "devs", name: "Skylar Parrish", title: "node.js Developer", img: "https://cdn.balkan.app/shared/8.jpg" },
    { id: 13, stpid: "devs", name: "Ashton Koch", title: "C# Developer", img: "https://cdn.balkan.app/shared/9.jpg" },
    { id: 14, stpid: "sales", name: "Bret Fraser", title: "Sales", img: "https://cdn.balkan.app/shared/13.jpg" },
    { id: 15, stpid: "sales", name: "Steff Haley", title: "Sales", img: "https://cdn.balkan.app/shared/14.jpg" }

 */



export default class OrganizationChartGenerator extends AIGenerator{

    constructor(client, language){
        super(client, language);

        this.contexts = null

        this.previousMessages = [{
            role: 'system', 
            content: `
          너는 회사의 인사관리자야 다음의 조직도 관리 기능을 할거야.  
            - 신규사원의 입사
            :  이름, 이메일 (유일키), 직급, 소속팀, 역할 등을 입력 받아야해.
            - 팀 등록 수정 삭제
            : 팀명, 상위팀명, 소속직원명단을 받아야 해.
            - 역할 등록 수정 삭제
            : 역할명, 역할설명, 역할 지정된 직원명단
            - 해당 담당직원 찾기:
            예를들어 교육부서의 회계담당을 찾아줘라고 하면 교수팀내 회계역할을 갖춘사람을 찾아서 명단을 리턴해주면 돼.   

            - 조직도 반영 해줘 or 조직도를 그려줘:
            사용자가 조직도를 이제 반영해줘.. 라고 말하면, 다음과 같은 json 포맷으로 조직도를 리턴해줘 (json key 값을 바꾸면 안되고, json만 리턴해):


{
  "organizationChart": [
    { "id": "개발팀", "name": "개발팀", "description": "개발팀", "team": true }, { "id": "jyjang@uengine.org", "name": "장진영", "pid": "개발팀", "role": "CTO" }, { "id": "BPM팀", "name": "BPM팀", "description": "BPM팀", "team": true }, { "id": "sanghoon@uengine.org", "name": "김상훈", "pid": "BPM팀" }, { "id": "이수헌", "name": "이수헌", "pid": "BPM팀" }, { "id": "양성원", "name": "양성원", "pid": "BPM팀" }, { "id": "오순영", "name": "오순영", "pid": "BPM팀", "role": "회계담당" }, { "id": "인사팀", "name": "인사팀", "description": "인사팀", "team": true }, { "id": "서원주", "name": "서원주", "pid": "인사팀" }, { "id": "강서구", "name": "강서구", "pid": "인사팀" }, { "id": "교육팀", "name": "교육팀", "description": "교육팀", "team": true }, { "id": "sjjung@uengine.org", "name": "정석진", "pid": "교육팀", "role": "팀장" }, { "id": "배동재", "name": "배동재", "pid": "교육팀" }, { "id": "김근영", "name": "김근영", "pid": "교육팀", "role": "회계담당" } 
   
]}


            자, 그럼 시작한다.

          

`
            }];
    }

    createPrompt(){
       return this.client.newMessage
    }

}