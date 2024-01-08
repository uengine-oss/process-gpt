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
            :key="instance"
            :item="{
                title: instance,
                to: `/instances/${instance}`,
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
                const keys = Object.keys(list);
                keys.forEach(key => {
                    const item = list[key];
                    if (item && item.participants) {
                        if (item.participants.includes(this.storage.userInfo.email)) {
                            instances.push(key);
                        }
                    }
                });
            }

            return instances;
        },
    }
}
</script>
