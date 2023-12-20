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

        this.getList("definitions");
        this.getList("instances");
    },
    methods: {
        async getList(path) {
            let list = await this.storage.list(`db://${path}`);
            if (list) {
                list = Object.values(list);
                list.forEach(item => {
                    if (item && item.model) {
                        this[path].push(partialParse(item.model));
                    }
                });
            }
        }
    }
}
</script>
