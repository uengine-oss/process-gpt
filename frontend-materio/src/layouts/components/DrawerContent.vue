<template>
    <ul>
        <VerticalNavSectionTitle :item="{ heading: '정의 관리' }" />
        <VerticalNavLink
            :item="{
                title: '조직도 정의',
                to: '/organization',
                icon: 'mdi-plus'
            }"
        />
        <VerticalNavLink
            :item="{
                title: '프로세스 정의',
                to: '/definitions',
                icon: 'mdi-plus'
            }"
        />
        <VerticalNavLink
            v-for="definition in definitions"
            :key="definition.processDefinitionId"
            :item="{
                title: definition.processDefinitionName,
                to: `/definitions/${definition.processDefinitionId}`,
            }"
        />
        
        <VerticalNavSectionTitle :item="{ heading: '프로세스 실행' }" />
        <VerticalNavLink
            :item="{
                title: '프로세스 실행',
                to: '/instances',
                icon: 'mdi-plus'
            }"
        />
        <VerticalNavLink
            v-for="instance in instances"
            :key="instance.processInstanceId"
            :item="{
                title: instance.processInstanceId,
                to: `/instances/${instance.processInstanceId}`,
            }"
        />
        
        <VerticalNavSectionTitle :item="{ heading: 'ToDoList' }" />
        <VerticalNavLink
            :item="{
                title: '할 일',
                to: '/todolist',
            }"
        />
    </ul>
</template>

<script>
import { VerticalNavLink, VerticalNavSectionTitle } from '@layouts';

import partialParse from "partial-json-parser";
import CommonStorageBase from "@/components/storage/CommonStorageBase";

export default {
    components: {
        VerticalNavLink, 
        VerticalNavSectionTitle
    },
    data: () => ({
        storage: null,
        definitions: [],
        instances: []
    }),
    async created() {
        this.storage = new CommonStorageBase(this);
        await this.storage.loginUser();

        if (this.storage.userInfo && this.storage.userInfo.name) {
            this.definitions = await this.getDefinitionList();
            this.instances = await this.getInstanceList();
        }
        
    },
    methods: {
        async getDefinitionList() {
            var definitions = [];
            let list = await this.storage.list(`db://definitions`);
            if (list) {
                list = Object.values(list);
                list.forEach(item => {
                    if (item && item.model) {
                        definitions.push(partialParse(item.model));
                    }
                });
            }

            return definitions;
        },
        async getInstanceList() {
            var instances = [];
            let list = await this.storage.list(`db://instances`);
            if (list) {
                list = Object.values(list);
                list.forEach(item => {
                    if (item && item.model && item.model.length > 0) {
                        //NOTE: item.model 이라는 표현보다는 item.data가 나아보입니다. model 은 어떠한 메타모델 (정의)를 뜻합니다. 인스턴스 한건의 데이터이기 때문에 model 이라는 표현은 어색합니다.
                        //item.model.forEach(modelText => {
                            let instance = JSON.parse(item.model)

                            //let instance = partialParse(modelText); //NOTE: partialParse 는 stream 에서 받아올때 이외에는 사용하지 마세요.
                            //NOTE: 내가 참여자인지 아닌지 체크하는 로직이 필요합니다. 참여자 전체 목록을 가진 프로퍼티가 있어야 하고, 이런 목록성 데이터는 JSON 문자열로 담는 것은 어색합니다.
                            if (instance && instance.currentUserEmail && instance.nextUserEmail){// && (instance.currentUserEmail == this.storage.userInfo.email || instance.nextUserEmail == this.storage.userInfo.email)) {
                                instances.push(instance);
                            }
                        //})
                    }
                });
            }

            return instances;
        },
    }
}
</script>
